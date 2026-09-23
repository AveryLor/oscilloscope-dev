"""The scope window: connection controls, the trace plot, a readout panel,
and the control dock that sends SET_* commands back to the ESP32."""

from __future__ import annotations

import queue
import time

import pyqtgraph as pg
import serial
from PySide6.QtCore import Qt, QSignalBlocker, QTimer
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDockWidget,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QSlider,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from . import control
from .frame import Frame
from .link import BadEvent, DEFAULT_BAUD, DisconnectedEvent, FrameEvent, Link, list_ports

TRACE = "#33FF66"
TRACE_FILL = (0x33, 0xFF, 0x66, 70)
TRIG_LEVEL = "#FF9020"
TRIG_POS = "#20A0FF"
WARN = "#FF3B30"


def fmt_volts(v: float) -> str:
    a = abs(v)
    if a >= 1.0:
        return f"{v:.2f} V"
    if a >= 1e-3:
        return f"{v * 1e3:.1f} mV"
    return f"{v * 1e6:.0f} µV"


def fmt_secs(s: float) -> str:
    a = abs(s)
    if a >= 1.0:
        return f"{s:.2f} s"
    if a >= 1e-3:
        return f"{s * 1e3:.2f} ms"
    if a >= 1e-6:
        return f"{s * 1e6:.2f} µs"
    return f"{s * 1e9:.0f} ns"


class MainWindow(QMainWindow):
    def __init__(self, port: str | None = None, baud: int = DEFAULT_BAUD) -> None:
        super().__init__()
        self.setWindowTitle("Oscilloscope")
        self.resize(1100, 640)

        self.link: Link | None = None
        self.latest: Frame | None = None
        self.last_seq: int | None = None
        self.dropped = 0
        self.bad = 0
        self.last_bad: str | None = None
        self.frames = 0
        self.fps = 0.0
        self._fps_since = time.monotonic()
        self._synced_controls = False

        self._build_top_bar()
        self._build_plot()
        self._build_readout_dock()
        self._build_control_dock()
        self._set_controls_enabled(False)

        central = QWidget()
        layout = QVBoxLayout(central)
        layout.setContentsMargins(4, 4, 4, 4)
        layout.addWidget(self._top_bar)
        layout.addWidget(self.plot)
        self.setCentralWidget(central)

        self._rescan()
        if port is not None:
            idx = self.port_combo.findText(port)
            if idx == -1:
                self.port_combo.addItem(port)
                idx = self.port_combo.findText(port)
            self.port_combo.setCurrentIndex(idx)
            self.baud_spin.setValue(baud)
            self._connect()

        self._pump_timer = QTimer(self)
        self._pump_timer.setInterval(16)
        self._pump_timer.timeout.connect(self._pump)
        self._pump_timer.start()

    # ---- UI construction ----------------------------------------------

    def _build_top_bar(self) -> None:
        self._top_bar = QWidget()
        row = QHBoxLayout(self._top_bar)
        row.setContentsMargins(0, 0, 0, 0)

        self.port_combo = QComboBox()
        self.port_combo.setMinimumWidth(160)
        self.rescan_btn = QPushButton("Rescan")
        self.rescan_btn.clicked.connect(self._rescan)

        self.baud_spin = QSpinBox()
        self.baud_spin.setRange(1200, 2_000_000)
        self.baud_spin.setValue(DEFAULT_BAUD)
        self.baud_spin.setGroupSeparatorShown(True)

        self.connect_btn = QPushButton("Connect")
        self.connect_btn.clicked.connect(self._on_connect_clicked)

        self.status_label = QLabel("not connected")

        row.addWidget(QLabel("Port:"))
        row.addWidget(self.port_combo)
        row.addWidget(self.rescan_btn)
        row.addWidget(QLabel("Baud:"))
        row.addWidget(self.baud_spin)
        row.addWidget(self.connect_btn)
        row.addWidget(self.status_label, stretch=1)

    def _build_plot(self) -> None:
        self.plot = pg.PlotWidget()
        self.plot.showGrid(x=True, y=True, alpha=0.3)
        self.plot.setLabel("bottom", "Time", units="s")
        self.plot.setLabel("left", "Voltage", units="V")
        self.plot.setBackground("#101010")

        self._env_upper = self.plot.plot(pen=pg.mkPen(TRACE, width=1))
        self._env_lower = self.plot.plot(pen=pg.mkPen(TRACE, width=1))
        self._fill = pg.FillBetweenItem(self._env_upper, self._env_lower, brush=pg.mkBrush(*TRACE_FILL))
        self.plot.addItem(self._fill)
        self._midline = self.plot.plot(pen=pg.mkPen(TRACE, width=1.5))

        self._trig_level_line = pg.InfiniteLine(angle=0, pen=pg.mkPen(TRIG_LEVEL, style=Qt.DashLine))
        self._trig_pos_line = pg.InfiniteLine(angle=90, pen=pg.mkPen(TRIG_POS, style=Qt.DashLine))
        self.plot.addItem(self._trig_level_line)
        self.plot.addItem(self._trig_pos_line)
        self._trig_level_line.hide()
        self._trig_pos_line.hide()

        self._no_signal = pg.TextItem("no signal", anchor=(0.5, 0.5), color="#888888")
        self.plot.addItem(self._no_signal)
        self.plot.getViewBox().setAutoVisible(y=True)
        self.plot.setRange(xRange=(0, 1), yRange=(-1, 1), padding=0)

    def _build_readout_dock(self) -> None:
        dock = QDockWidget("Readout", self)
        dock.setFeatures(QDockWidget.NoDockWidgetFeatures)
        panel = QWidget()
        form = QFormLayout(panel)

        def add_row(label: str) -> QLabel:
            value = QLabel("–")
            form.addRow(label, value)
            return value

        self.lbl_volts_div = add_row("Volts/div")
        self.lbl_time_div = add_row("Time/div")
        self.lbl_samples = add_row("Samples")
        self.lbl_coupling = add_row("Coupling")
        self.lbl_input = add_row("Input")
        self.lbl_term = add_row("Termination")
        self.lbl_trigger = add_row("Trigger")
        self.lbl_prepost = add_row("Pre/post")
        self.lbl_acq = add_row("Acquisition")
        self.lbl_offset = add_row("Offset code")
        self.lbl_fps = add_row("Frames/s")
        self.lbl_dropped = add_row("Dropped")
        self.lbl_bad = add_row("Bad frames")

        self.lbl_overrange = QLabel("input clipping")
        self.lbl_overrange.setStyleSheet(f"color: {WARN}; font-weight: bold;")
        self.lbl_overrange.setVisible(False)
        form.addRow(self.lbl_overrange)

        self.lbl_last_bad = QLabel()
        self.lbl_last_bad.setStyleSheet(f"color: {WARN};")
        self.lbl_last_bad.setWordWrap(True)
        self.lbl_last_bad.setVisible(False)
        form.addRow(self.lbl_last_bad)

        dock.setWidget(panel)
        self.addDockWidget(Qt.RightDockWidgetArea, dock)

    def _build_control_dock(self) -> None:
        dock = QDockWidget("Controls", self)
        dock.setFeatures(QDockWidget.NoDockWidgetFeatures)
        panel = QWidget()
        col = QVBoxLayout(panel)

        self._deb_timebase = control.DebouncedSender(self._send)
        self._deb_hoffset = control.DebouncedSender(self._send)
        self._deb_trigger = control.DebouncedSender(self._send)
        self._deb_vertical = control.DebouncedSender(self._send)
        self._deb_coupling = control.DebouncedSender(self._send)
        self._deb_term = control.DebouncedSender(self._send)

        # -- Timebase --
        tb_group = QGroupBox("Timebase")
        tb_form = QFormLayout(tb_group)
        self.dec_factor_spin = QSpinBox()
        self.dec_factor_spin.setRange(0, 0xFFFF)
        self.dec_factor_spin.valueChanged.connect(self._on_timebase_changed)
        tb_form.addRow("Decimation factor", self.dec_factor_spin)
        col.addWidget(tb_group)

        # -- Horizontal offset --
        ho_group = QGroupBox("Horizontal Offset")
        ho_form = QFormLayout(ho_group)
        self.pre_spin = QSpinBox()
        self.pre_spin.setRange(0, 0xFFFF)
        self.pre_spin.setValue(1024)
        self.post_spin = QSpinBox()
        self.post_spin.setRange(0, 0xFFFF)
        self.post_spin.setValue(1024)
        self.pre_spin.valueChanged.connect(self._on_hoffset_changed)
        self.post_spin.valueChanged.connect(self._on_hoffset_changed)
        ho_form.addRow("Pre-trigger samples", self.pre_spin)
        ho_form.addRow("Post-trigger samples", self.post_spin)
        col.addWidget(ho_group)

        # -- Trigger --
        # trig_src/trig_edge/trig_hyst are never echoed by the sample stream
        # (see docs/STREAM.md's frame layout), so these three cannot be synced
        # from a connected device -- only trig_level can. They start at the
        # firmware's own boot defaults (stream.c) and track whatever the GUI
        # last sent from here on.
        tg_group = QGroupBox("Trigger")
        tg_form = QFormLayout(tg_group)
        self.level_slider = QSlider(Qt.Horizontal)
        self.level_slider.setRange(0, 1023)
        self.level_slider.setValue(512)
        self.src_combo = QComboBox()
        self.src_combo.addItems(["Level", "External", "Force"])
        self.edge_combo = QComboBox()
        self.edge_combo.addItems(["Rising", "Falling", "Either"])
        self.hyst_spin = QSpinBox()
        self.hyst_spin.setRange(0, 255)
        self.hyst_spin.setValue(4)
        self.level_slider.valueChanged.connect(self._on_trigger_changed)
        self.src_combo.currentIndexChanged.connect(self._on_trigger_changed)
        self.edge_combo.currentIndexChanged.connect(self._on_trigger_changed)
        self.hyst_spin.valueChanged.connect(self._on_trigger_changed)
        tg_form.addRow("Level (code)", self.level_slider)
        tg_form.addRow("Source", self.src_combo)
        tg_form.addRow("Edge", self.edge_combo)
        tg_form.addRow("Hysteresis", self.hyst_spin)
        col.addWidget(tg_group)

        # -- Vertical --
        v_group = QGroupBox("Vertical")
        v_form = QFormLayout(v_group)
        self.atten_combo = QComboBox()
        self.atten_combo.addItems(["1x", "10x", "100x"])
        self.preamp_combo = QComboBox()
        self.preamp_combo.addItems(["Low Gain (18.8 dB)", "High Gain (38.8 dB)"])
        self.lmh_atten_spin = QSpinBox()
        self.lmh_atten_spin.setRange(0, 10)
        self.offset_slider = QSlider(Qt.Horizontal)
        self.offset_slider.setRange(0, 4095)
        self.offset_slider.setValue(2048)
        self.atten_combo.currentIndexChanged.connect(self._on_vertical_changed)
        self.preamp_combo.currentIndexChanged.connect(self._on_vertical_changed)
        self.lmh_atten_spin.valueChanged.connect(self._on_vertical_changed)
        self.offset_slider.valueChanged.connect(self._on_vertical_changed)
        v_form.addRow("Input divider", self.atten_combo)
        v_form.addRow("Preamp", self.preamp_combo)
        v_form.addRow("Ladder attenuation", self.lmh_atten_spin)
        v_form.addRow("Offset code", self.offset_slider)
        col.addWidget(v_group)

        # -- Coupling / termination --
        ct_group = QGroupBox("Input")
        ct_form = QFormLayout(ct_group)
        self.dc_checkbox = QCheckBox("DC coupled")
        self.term_checkbox = QCheckBox("50 Ω termination")
        self.dc_checkbox.toggled.connect(self._on_coupling_changed)
        self.term_checkbox.toggled.connect(self._on_term_changed)
        ct_form.addRow(self.dc_checkbox)
        ct_form.addRow(self.term_checkbox)
        col.addWidget(ct_group)

        col.addStretch(1)

        self._control_widgets = [
            self.dec_factor_spin, self.pre_spin, self.post_spin,
            self.level_slider, self.src_combo, self.edge_combo, self.hyst_spin,
            self.atten_combo, self.preamp_combo, self.lmh_atten_spin, self.offset_slider,
            self.dc_checkbox, self.term_checkbox,
        ]

        dock.setWidget(panel)
        self.addDockWidget(Qt.LeftDockWidgetArea, dock)

    def _set_controls_enabled(self, enabled: bool) -> None:
        for w in self._control_widgets:
            w.setEnabled(enabled)

    # ---- Connection lifecycle ------------------------------------------

    def _rescan(self) -> None:
        current = self.port_combo.currentText()
        self.port_combo.clear()
        ports = list_ports()
        self.port_combo.addItems(ports)
        idx = self.port_combo.findText(current)
        if idx != -1:
            self.port_combo.setCurrentIndex(idx)

    def _on_connect_clicked(self) -> None:
        if self.link is None:
            self._connect()
        else:
            self._disconnect()

    def _connect(self) -> None:
        port = self.port_combo.currentText()
        if not port:
            self.status_label.setText("no port selected")
            return
        try:
            self.link = Link(port, self.baud_spin.value())
        except serial.SerialException as exc:
            self.status_label.setText(f"{port}: {exc}")
            return

        self.status_label.setText(f"connected to {port}")
        self.last_seq = None
        self.dropped = 0
        self.bad = 0
        self.last_bad = None
        self._synced_controls = False
        self.connect_btn.setText("Disconnect")
        self.port_combo.setEnabled(False)
        self.rescan_btn.setEnabled(False)
        self._set_controls_enabled(True)

    def _disconnect(self) -> None:
        if self.link is not None:
            self.link.close()
            self.link = None
        self.status_label.setText("not connected")
        self.connect_btn.setText("Connect")
        self.port_combo.setEnabled(True)
        self.rescan_btn.setEnabled(True)
        self._set_controls_enabled(False)

    def _send(self, line: str) -> bool:
        if self.link is None:
            return False
        return self.link.send(line)

    # ---- Control -> command wiring --------------------------------------

    def _on_timebase_changed(self) -> None:
        try:
            line = control.fmt_set_timebase(self.dec_factor_spin.value())
        except ValueError:
            return
        self._deb_timebase.submit(line)

    def _on_hoffset_changed(self) -> None:
        try:
            line = control.fmt_set_hoffset(self.pre_spin.value(), self.post_spin.value())
        except ValueError:
            return
        self._deb_hoffset.submit(line)

    def _on_trigger_changed(self) -> None:
        try:
            line = control.fmt_set_trigger(
                self.level_slider.value(),
                self.src_combo.currentIndex(),
                self.edge_combo.currentIndex(),
                self.hyst_spin.value(),
            )
        except ValueError:
            return
        self._deb_trigger.submit(line)

    def _on_vertical_changed(self) -> None:
        try:
            line = control.fmt_set_vertical(
                self.atten_combo.currentIndex(),
                self.preamp_combo.currentIndex(),
                self.lmh_atten_spin.value(),
                self.offset_slider.value(),
            )
        except ValueError:
            return
        self._deb_vertical.submit(line)

    def _on_coupling_changed(self, dc_coupled: bool) -> None:
        self._deb_coupling.submit(control.fmt_set_coupling(dc_coupled))

    def _on_term_changed(self, term_50r: bool) -> None:
        self._deb_term.submit(control.fmt_set_term(term_50r))

    def _sync_controls_from_frame(self, f: Frame) -> None:
        # Only fields the sample stream actually carries (see docs/STREAM.md)
        # can be synced; trig_src/trig_edge/trig_hyst are GUI-only state.
        blockers = [QSignalBlocker(w) for w in self._control_widgets]
        self.dec_factor_spin.setValue(f.dec_factor)
        self.pre_spin.setValue(f.pre_count)
        self.post_spin.setValue(f.post_count)
        self.level_slider.setValue(f.trig_level)
        self.atten_combo.setCurrentIndex(f.afe_atten)
        self.preamp_combo.setCurrentIndex(1 if f.preamp_hg else 0)
        self.lmh_atten_spin.setValue(f.lmh_atten)
        self.offset_slider.setValue(f.dac_offset)
        self.dc_checkbox.setChecked(f.dc_coupled)
        self.term_checkbox.setChecked(f.term_50r)
        del blockers

    # ---- Event pump ------------------------------------------------------

    def _pump(self) -> None:
        if self.link is None:
            return

        disconnect_reason: str | None = None
        while True:
            try:
                event = self.link.events.get_nowait()
            except queue.Empty:
                break

            if isinstance(event, FrameEvent):
                f = event.frame
                if self.last_seq is not None:
                    gap = (f.seq - self.last_seq) & 0xFFFFFFFF
                    self.dropped += max(0, gap - 1)
                self.last_seq = f.seq
                self.latest = f
                self.frames += 1
                if not self._synced_controls:
                    self._sync_controls_from_frame(f)
                    self._synced_controls = True
            elif isinstance(event, BadEvent):
                self.bad += 1
                self.last_bad = event.reason
            elif isinstance(event, DisconnectedEvent):
                disconnect_reason = event.reason

        if disconnect_reason is not None:
            self.link = None
            self.status_label.setText(f"link lost: {disconnect_reason}")
            self.connect_btn.setText("Connect")
            self.port_combo.setEnabled(True)
            self.rescan_btn.setEnabled(True)
            self._set_controls_enabled(False)

        now = time.monotonic()
        elapsed = now - self._fps_since
        if elapsed >= 1.0:
            self.fps = self.frames / elapsed
            self.frames = 0
            self._fps_since = now

        if self.latest is not None:
            self._no_signal.hide()
            self._update_plot(self.latest)
            self._update_readout(self.latest)

    # ---- Rendering ---------------------------------------------------

    def _update_plot(self, f: Frame) -> None:
        n = len(f.cols)
        dur = f.duration()
        xs = [i / (n - 1) * dur for i in range(n)] if n > 1 else [0.0] * n
        ymins = [f.code_to_volts(lo) for lo, _hi in f.cols]
        ymaxs = [f.code_to_volts(hi) for _lo, hi in f.cols]
        mids = [f.code_to_volts((lo + hi) // 2) for lo, hi in f.cols]

        self._env_upper.setData(xs, ymaxs)
        self._env_lower.setData(xs, ymins)
        self._midline.setData(xs, mids)

        self._trig_level_line.setPos(f.code_to_volts(f.trig_level))
        self._trig_level_line.show()

        frac = f.trig_fraction()
        if frac is not None:
            self._trig_pos_line.setPos(frac * dur)
            self._trig_pos_line.show()
        else:
            self._trig_pos_line.hide()

    def _update_readout(self, f: Frame) -> None:
        vpc = f.volts_per_count()
        self.lbl_volts_div.setText(fmt_volts(vpc * 128.0))  # 8 vertical divisions over 1024 codes
        self.lbl_time_div.setText(fmt_secs(f.duration() / 10.0))  # 10 horizontal divisions
        self.lbl_samples.setText(str(f.sample_count))
        self.lbl_coupling.setText("DC" if f.dc_coupled else "AC")
        self.lbl_input.setText(["1x", "10x", "100x"][f.afe_atten] if f.afe_atten < 3 else "?")
        self.lbl_term.setText("50 Ω" if f.term_50r else "1 MΩ")
        self.lbl_trigger.setText("triggered" if f.triggered else "auto")
        self.lbl_prepost.setText(f"{f.pre_count} / {f.post_count}")
        self.lbl_acq.setText("peak detect" if f.peak else "sampled")
        self.lbl_offset.setText(str(f.dac_offset))
        self.lbl_fps.setText(f"{self.fps:.1f}")
        self.lbl_dropped.setText(str(self.dropped))
        self.lbl_bad.setText(str(self.bad))

        self.lbl_overrange.setVisible(f.overrange)
        if self.last_bad is not None:
            self.lbl_last_bad.setText(f"last bad frame: {self.last_bad}")
            self.lbl_last_bad.setVisible(True)
        else:
            self.lbl_last_bad.setVisible(False)

    def closeEvent(self, event) -> None:  # noqa: N802 (Qt override)
        if self.link is not None:
            self.link.close()
        super().closeEvent(event)
