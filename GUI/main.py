import os
import subprocess
from PyQt6.QtGui import QPainter, QColor, QShortcut, QKeySequence, QPen, QFont, QIcon
from PyQt6.QtWidgets import (
    QMainWindow, QApplication, QWidget, QLabel, QPushButton,
    QGridLayout, QHBoxLayout, QVBoxLayout, QSlider, QCheckBox,
    QLineEdit, QMessageBox, QDialog, QTextEdit
)
from PyQt6.QtCore import Qt, QSize, QUrl, QRect, QTimer
from PyQt6.QtMultimedia import QMediaPlayer, QAudioOutput
from PyQt6.QtMultimediaWidgets import QVideoWidget
from qt_material import apply_stylesheet
import sys
import os

from FrameMonkey.GUI.Functions import openFile


class MainWindow(QMainWindow):
    def __init__(self, inputFile=None):
        super().__init__()
        # self.setFixedSize(QSize(1920, 1080))
        self.setWindowTitle("FrameMonkey")

        # Set window icon
        icon_path = r"C:\!Dev\FrameMonkey\FrameMonkey\GUI\Assets\FrameMonkey_Icon_Transparent.png"
        self.setWindowIcon(QIcon(icon_path))

        # Create all buttons first
        self.prevFrameBtn = QPushButton("◀")
        self.playButton = QPushButton("⏯")
        self.nextFrameBtn = QPushButton("▶")
        self.compressBtn = QPushButton("Compress")
        browseFileBtn = QPushButton("Browse")

        # Set button IDs for styling
        self.compressBtn.setObjectName("compressBtn")
        self.prevFrameBtn.setObjectName("frameBtn")
        self.playButton.setObjectName("frameBtn")
        self.nextFrameBtn.setObjectName("frameBtn")

        # Connect button signals
        self.prevFrameBtn.clicked.connect(self.previousFrame)
        self.playButton.clicked.connect(self.togglePlayback)
        self.nextFrameBtn.clicked.connect(self.nextFrame)
        self.compressBtn.clicked.connect(self.executeCompression)
        browseFileBtn.clicked.connect(self.handleFileOpen)

        # Set the stylesheet
        self.setStyleSheet("""
            QMainWindow, QWidget {
                background-color: #343434;
                color: white;
            }
            QPushButton {
                background-color: #FFD700;
                color: black;
                padding: 5px;
                border-radius: 3px;
                min-width: 60px;
            }
            QPushButton#compressBtn {
                background-color: #FF4444;
                color: white;
                font-weight: bold;
            }
            QPushButton#frameBtn {
                background-color: #FFD700;
                color: black;
                font-weight: bold;
                max-width: 40px;
                padding: 2px;
            }
            QLabel {
                color: white;
                margin-right: 5px;
            }
            QLineEdit {
                max-width: 60px;
                background-color: #444444;
                color: white;
                padding: 3px;
                border: 1px solid #555555;
            }
            QSlider {
                background-color: transparent;
            }
            QCheckBox {
                color: white;
                spacing: 5px;
            }
            QCheckBox::indicator {
                width: 15px;
                height: 15px;
                background-color: #444444;
                border: 1px solid #555555;
            }
            QCheckBox::indicator:checked {
                background-color: #FFD700;
            }
        """)

        # Create a central widget and main layout
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        layout = QGridLayout(self.central_widget)

        # Input File Component
        fileControlLayout = QHBoxLayout()
        self.fileNameLabel = QLabel(inputFile)
        fileControlLayout.addWidget(self.fileNameLabel)
        fileControlLayout.addWidget(browseFileBtn)

        # Video Player Component - with error handling
        try:
            # Create video widget first
            self.videoWidget = QVideoWidget()
            self.videoWidget.setMinimumSize(960, 540)

            # Create media player with audio output
            try:
                self.player = QMediaPlayer()
                self.audioOutput = QAudioOutput()
                self.player.setAudioOutput(self.audioOutput)
                print("QMediaPlayer and QVideoWidget initialized successfully")
            except Exception as e:
                print(f"Error initializing media player: {e}")

            # Set video output
            self.player.setVideoOutput(self.videoWidget)
            self.videoWidget.setAspectRatioMode(Qt.AspectRatioMode.KeepAspectRatio)

        except Exception as e:
            print(f"Error initializing media player: {str(e)}")
            QMessageBox.critical(self, "Error", f"Failed to initialize media player components: {str(e)}")
            return

        # Create a widget for file controls
        fileControlWidget = QWidget()
        fileControlWidget.setLayout(fileControlLayout)
        fileControlWidget.setMaximumHeight(50)

        # Layout adjustments for more video space
        layout.setRowStretch(1, 4)
        layout.addWidget(fileControlWidget, 0, 0, 1, 7)
        layout.addWidget(self.videoWidget, 1, 0, 6, 7)

        # Add dual slider
        self.dualSlider = DualSlider()
        self.dualSlider.slider.valueChanged.connect(self.handleSliderValueChanged)
        layout.addWidget(self.dualSlider, 7, 0, 1, 7)

        # Add frame control buttons with reduced height
        frameControlLayout = QHBoxLayout()

        # Make all buttons more compact
        for btn in [self.prevFrameBtn, self.playButton, self.nextFrameBtn]:
            btn.setMaximumHeight(25)
            btn.setMaximumWidth(40)

        frameControlLayout.addStretch()
        frameControlLayout.addWidget(self.prevFrameBtn)
        frameControlLayout.addWidget(self.playButton)
        frameControlLayout.addWidget(self.nextFrameBtn)
        frameControlLayout.addStretch()

        # Frame controls
        frameControlWidget = QWidget()
        frameControlWidget.setLayout(frameControlLayout)
        frameControlWidget.setMaximumHeight(40)
        layout.addWidget(frameControlWidget, 8, 0, 1, 7)

        # Checkbox layout with shorter labels
        checkboxLayout = QHBoxLayout()
        checkboxLayout.setSpacing(20)  # Space between checkbox groups

        # Create horizontal layouts for each checkbox+label pair
        trimLayout = QHBoxLayout()
        trimLayout.setSpacing(2)
        self.trimVideo = QCheckBox()
        trimVideoLabel = QLabel("Trim")
        trimLayout.addWidget(self.trimVideo)
        trimLayout.addWidget(trimVideoLabel)

        twoPassLayout = QHBoxLayout()
        twoPassLayout.setSpacing(2)
        self.twoPass = QCheckBox()
        twoPassLabel = QLabel("Two Pass")
        twoPassLayout.addWidget(self.twoPass)
        twoPassLayout.addWidget(twoPassLabel)

        hwAccelLayout = QHBoxLayout()
        hwAccelLayout.setSpacing(2)
        self.hwAccel = QCheckBox()
        self.hwAccel.setChecked(True)
        hwAccelLabel = QLabel("HW Accel")
        hwAccelLayout.addWidget(self.hwAccel)
        hwAccelLayout.addWidget(hwAccelLabel)

        # Add tooltips
        self.trimVideo.setToolTip("Enable video trimming")
        self.twoPass.setToolTip("Enable two-pass encoding for better quality")
        self.hwAccel.setToolTip("Enable hardware acceleration for faster encoding")

        # Add each pair to the main layout
        checkboxLayout.addLayout(trimLayout)
        checkboxLayout.addLayout(twoPassLayout)
        checkboxLayout.addLayout(hwAccelLayout)
        checkboxLayout.addStretch()

        checkboxWidget = QWidget()
        checkboxWidget.setLayout(checkboxLayout)
        checkboxWidget.setMaximumHeight(40)
        layout.addWidget(checkboxWidget, 9, 0, 1, 7)

        # Quality settings
        qualityLayout = QHBoxLayout()
        qualityLayout.setSpacing(20)  # Space between groups

        # Size input group
        sizeLayout = QHBoxLayout()
        sizeLayout.setSpacing(2)
        self.fileSize = QLineEdit("10")
        self.fileSize.setFixedWidth(40)
        sizeLayout.addWidget(self.fileSize)

        # Quality input group
        qualityInputLayout = QHBoxLayout()
        qualityInputLayout.setSpacing(2)
        qualityLabel = QLabel("Quality(MB)")
        self.encodingSpeed = QLineEdit("6")
        self.encodingSpeed.setFixedWidth(40)
        qinfoLabel = QLabel("1-Fast, 6-Slow")
        qualityInputLayout.addWidget(qualityLabel)
        qualityInputLayout.addWidget(self.encodingSpeed)
        qualityInputLayout.addWidget(qinfoLabel)

        # Add each group to the main layout
        qualityLayout.addLayout(sizeLayout)
        qualityLayout.addLayout(qualityInputLayout)
        qualityLayout.addStretch()

        qualityWidget = QWidget()
        qualityWidget.setLayout(qualityLayout)
        qualityWidget.setMaximumHeight(40)
        layout.addWidget(qualityWidget, 10, 0, 1, 7)

        # Add compress button at the bottom
        self.compressBtn.setMaximumHeight(40)
        self.compressBtn.setMinimumWidth(100)
        layout.addWidget(self.compressBtn, 11, 0, 1, 7)

        # Connect media player signals
        try:
            self.player.positionChanged.connect(self.updatePosition)
            self.player.durationChanged.connect(self.updateDuration)
            self.player.errorOccurred.connect(self.handleError)
        except Exception as e:
            print(f"Error connecting media player signals: {e}")
            QMessageBox.warning(self, "Warning", "Some media player features may not be available")

        # Set up keyboard shortcuts
        self.setupShortcuts()

        # Set default audio volume
        self.audioOutput.setVolume(1.0)

        # Load the input file if provided and it exists
        if inputFile and os.path.isfile(inputFile):
            self.fileNameLabel.setText(inputFile)
            try:
                self.player.setSource(QUrl.fromLocalFile(inputFile))
                self.player.play()
            except Exception as e:
                print(f"Error loading input file: {e}")

    def setupShortcuts(self):
        # Left arrow for previous frame
        prevFrameShortcut = QShortcut(QKeySequence(Qt.Key.Key_Left), self)
        prevFrameShortcut.activated.connect(self.previousFrame)

        # Right arrow for next frame
        nextFrameShortcut = QShortcut(QKeySequence(Qt.Key.Key_Right), self)
        nextFrameShortcut.activated.connect(self.nextFrame)

        # Space for play/pause
        playPauseShortcut = QShortcut(QKeySequence(Qt.Key.Key_Space), self)
        playPauseShortcut.activated.connect(self.togglePlayback)

    def previousFrame(self):
        if hasattr(self, 'frameTime') and self.player.duration() > 0:
            currentPos = self.player.position()
            newPos = max(0, currentPos - int(self.frameTime))
            self.player.pause()  # Pause when stepping frames
            self.player.setPosition(newPos)
            self.playButton.setText("⏯")

    def nextFrame(self):
        if hasattr(self, 'frameTime') and self.player.duration() > 0:
            currentPos = self.player.position()
            newPos = min(self.player.duration(), currentPos + int(self.frameTime))
            self.player.pause()  # Pause when stepping frames
            self.player.setPosition(newPos)
            self.playButton.setText("⏯")

    def updatePosition(self, position):
        # Update slider position
        if self.player.duration() > 0:
            sliderValue = int((position * 1000) / self.player.duration())
            # Block signals temporarily to prevent feedback loop
            self.dualSlider.slider.blockSignals(True)
            self.dualSlider.slider.setValue(sliderValue)
            self.dualSlider.slider.blockSignals(False)
            # Update current position in dual slider
            self.dualSlider.currentPos = sliderValue
            self.dualSlider.updateTimeLabels()
            self.dualSlider.update()

    def updateDuration(self, duration):
        self.dualSlider.setDuration(duration / 1000)  # Convert to seconds
        # Set a default frame time of 1/30th of a second if we can't get the actual frame rate
        self.frameTime = 1000 / 30  # Default to 30fps in milliseconds

        # Try to get media format information if available
        try:
            mediaFormat = self.player.mediaFormat()
            if mediaFormat.isValid():
                frameRate = mediaFormat.frameRate()
                if frameRate > 0:
                    self.frameTime = 1000 / frameRate  # Frame duration in milliseconds
        except Exception as e:
            print(f"Could not get frame rate, using default 30fps: {e}")

    def handleFileOpen(self):
        fileName = openFile()
        if fileName:
            self.fileNameLabel.setText(fileName)
            self.player.setSource(QUrl.fromLocalFile(fileName))
            self.player.play()

    def togglePlayback(self):
        if self.player.playbackState() == QMediaPlayer.PlaybackState.PlayingState:
            self.player.pause()
            self.playButton.setText("⏯")
        else:
            self.player.play()
            self.playButton.setText("⏸")

    def handleError(self, error, errorString):
        if error != QMediaPlayer.Error.NoError:
            QMessageBox.warning(self, "Media Error", f"Error playing media: {errorString}")

    def handleSliderValueChanged(self, value):
        if self.player.duration() > 0:
            # Convert slider value (0-1000) to video position
            newPosition = int((value * self.player.duration()) / 1000)
            self.player.setPosition(newPosition)

    def getTrimTimes(self):
        """Return the start and end trim times in seconds"""
        return (self.dualSlider.getStartTime(), self.dualSlider.getEndTime())

    def executeCompression(self):
        startTime, endTime = self.getTrimTimes()
        inputFile = self.fileNameLabel.text()
        targetSize = int(self.fileSize.text())
        twoPass = self.twoPass.isChecked()
        hwAccel = self.hwAccel.isChecked()
        quality = int(self.encodingSpeed.text())

        # Format time values as HH:MM:SS.mmm
        def format_time(seconds):
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            secs = int(seconds % 60)
            ms = int((seconds % 1) * 1000)
            return f"{hours:02d}:{minutes:02d}:{secs:02d}.{ms:03d}"

        # Build the script arguments
        script_args = f'-inputFile "{inputFile}" -targetSizeMB {targetSize}'

        # Add trim parameters if trim video is checked
        if self.trimVideo.isChecked():
            formatted_start = format_time(startTime)
            formatted_end = format_time(endTime)
            script_args += f' -TrimStart "{formatted_start}" -TrimEnd "{formatted_end}"'

        # Add two-pass parameter if checked
        if twoPass:
            script_args += ' -twoPass'

        # Add hardware acceleration parameter if checked
        if hwAccel:
            script_args += ' -hwAccel'

        # Construct the PowerShell command
        ps_command = [
            'powershell',
            '-ExecutionPolicy', 'Bypass',
            '-NoProfile',
            '-NoExit',
            '-Command',
            f'cd "{frameMonkey_directory}"; Write-Host "Starting compression..."; ./compress_video.ps1 {script_args}'
        ]

        try:
            # Create process with new window
            process = subprocess.Popen(
                ps_command,
                creationflags=subprocess.CREATE_NEW_CONSOLE
            )

            QMessageBox.information(self, "Compression Started",
                                    "Compression has started in a new PowerShell window.\n"
                                    "The window will show the compression progress.")

        except Exception as e:
            QMessageBox.warning(self, "Error",
                                f"Failed to execute compression:\n"
                                f"Error type: {type(e)}\n"
                                f"Error message: {str(e)}")

        # Print the command for debugging
        print("Executing command:", ' '.join(ps_command))
    def update_output(self, process):
        # Read from stdout
        output = process.stdout.readline()
        if output:
            self.outputText.append(output.strip())
            self.outputText.verticalScrollBar().setValue(
                self.outputText.verticalScrollBar().maximum()
            )

        # Read from stderr
        error = process.stderr.readline()
        if error:
            self.outputText.append(f'<span style="color: red">{error.strip()}</span>')
            self.outputText.verticalScrollBar().setValue(
                self.outputText.verticalScrollBar().maximum()
            )

        # Check if process has finished
        if process.poll() is not None:
            self.timer.stop()
            if process.returncode == 0:
                self.outputText.append('<span style="color: green">Compression completed successfully!</span>')
            else:
                self.outputText.append('<span style="color: red">Compression failed with error code: '
                                       f'{process.returncode}</span>')

            # Clean up handles
            process.stdout.close()
            process.stderr.close()
class DualSlider(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.layout = QVBoxLayout(self)
        self.setMouseTracking(True)

        # Create the main slider
        self.slider = QSlider(Qt.Orientation.Horizontal)
        self.slider.setMinimum(0)
        self.slider.setMaximum(1000)
        # Install event filter on slider
        self.slider.installEventFilter(self)

        # Position markers
        self.startPos = 0
        self.endPos = 1000
        self.currentPos = 0
        self.duration = 0

        # Interaction states
        self.isDraggingStart = False
        self.isDraggingEnd = False
        self.isDraggingMain = False
        self.marker_width = 8
        self.hit_area = 15

        # Create time labels
        self.timeLayout = QHBoxLayout()
        self.currentTimeLabel = QLabel("00:00:00")
        self.startTimeLabel = QLabel("00:00:00")
        self.endTimeLabel = QLabel("00:00:00")

        self.timeLayout.addWidget(self.currentTimeLabel)
        self.timeLayout.addStretch()
        self.timeLayout.addWidget(self.startTimeLabel)
        self.timeLayout.addStretch()
        self.timeLayout.addWidget(self.endTimeLabel)

        self.layout.addLayout(self.timeLayout)
        self.layout.addWidget(self.slider)

        # Connect signals
        self.slider.valueChanged.connect(self.handleSliderValueChanged)

    def eventFilter(self, obj, event):
        if obj is self.slider:
            if event.type() == event.Type.MouseButtonPress and event.button() == Qt.MouseButton.LeftButton:
                pos = event.position().x()
                width = self.slider.width()

                # Calculate marker positions
                startPixels = int(self.startPos * width / 1000)
                endPixels = int(self.endPos * width / 1000)

                # Check for marker hits
                if abs(pos - startPixels) < self.hit_area:
                    self.isDraggingStart = True
                    print("Start marker hit")
                    return True  # Event handled
                elif abs(pos - endPixels) < self.hit_area:
                    self.isDraggingEnd = True
                    print("End marker hit")
                    return True  # Event handled
                #NEW: Handles clicks on empty slider area and teleports the slider there right away
                else:
                    relativePos = max(0, min(1000, int((pos * 1000) / width)))
                    self.slider.setValue(relativePos)
                    return True #event handled

            elif event.type() == event.Type.MouseMove:
                if self.isDraggingStart or self.isDraggingEnd:
                    pos = event.position().x()
                    width = self.slider.width()
                    relativePos = max(0, min(1000, int((pos * 1000) / width)))

                    if self.isDraggingStart:
                        self.startPos = min(self.endPos - 10, relativePos)
                    else:
                        self.endPos = max(self.startPos + 10, relativePos)

                    self.updateTimeLabels()
                    self.update()
                    return True  # Event handled

            elif event.type() == event.Type.MouseButtonRelease:
                self.isDraggingStart = False
                self.isDraggingEnd = False
                return True

        return super().eventFilter(obj, event)  # Pass unhandled events

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Get slider rectangle
        sliderRect = self.slider.geometry()

        # Draw the selection range
        start_x = int(sliderRect.x() + (sliderRect.width() * self.startPos / 1000))
        end_x = int(sliderRect.x() + (sliderRect.width() * self.endPos / 1000))
        y = int(sliderRect.y())
        height = int(sliderRect.height())
        range_width = end_x - start_x

        # Draw yellow range rectangle
        range_rect = QRect(start_x, y, range_width, height)
        painter.fillRect(range_rect, QColor(255, 255, 0, 100))

        # Draw current position indicator
        current_x = int(sliderRect.x() + (sliderRect.width() * self.currentPos / 1000))
        current_width = 4
        current_marker = QRect(
            current_x - current_width // 2,
            y,
            current_width,
            height
        )
        painter.fillRect(current_marker, QColor(0, 0, 0))

        # Draw start and end markers
        markerWidth = self.marker_width
        start_marker = QRect(
            int(start_x - markerWidth / 2),
            y,
            markerWidth,
            height
        )
        end_marker = QRect(
            int(end_x - markerWidth / 2),
            y,
            markerWidth,
            height
        )

        # Draw markers with hover/drag effects
        start_color = QColor(0, 255, 0, 230 if self.isDraggingStart else 180)
        end_color = QColor(255, 0, 0, 230 if self.isDraggingEnd else 180)

        painter.fillRect(start_marker, start_color)
        painter.fillRect(end_marker, end_color)

        # Draw borders for better visibility
        pen = QPen(QColor(0, 0, 0))
        pen.setWidth(1)
        painter.setPen(pen)
        painter.drawRect(start_marker)
        painter.drawRect(end_marker)

    def handleSliderValueChanged(self, value):
        self.currentPos = value
        self.updateTimeLabels()
        self.update()

    def setDuration(self, duration):
        self.duration = duration
        self.endPos = 1000
        self.updateTimeLabels()

    def updateTimeLabels(self):
        if self.duration > 0:
            current = self.currentPos * self.duration / 1000
            start = self.startPos * self.duration / 1000
            end = self.endPos * self.duration / 1000

            self.currentTimeLabel.setText(self.formatTime(current))
            self.startTimeLabel.setText(self.formatTime(start))
            self.endTimeLabel.setText(self.formatTime(end))

    def formatTime(self, seconds):
        hours = int(seconds / 3600)
        minutes = int((seconds % 3600) / 60)
        secs = int(seconds % 60)
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"

    def getStartTime(self):
        if self.duration > 0:
            return self.startPos * self.duration / 1000
        return 0

    def getEndTime(self):
        if self.duration > 0:
            return self.endPos * self.duration / 1000
        return 0


if __name__ == "__main__":
    path = os.getcwd()
    frameMonkey_directory = os.path.dirname(path)

    print(f"Current working directory: {frameMonkey_directory}")

    print("Starting application...")
    app = QApplication(sys.argv)
    print("QApplication created")

    # Process command line arguments
    inputFile = None
    if len(sys.argv) > 1:
        inputFile = sys.argv[1]
        if os.path.isfile(inputFile):
            print(f"Loading file from command line: {inputFile}")
        else:
            inputFile = os.getcwd()
    else:
        inputFile = os.getcwd()

    print("Creating main window...")
    window = MainWindow(inputFile=inputFile)
    print("Main window created")

    print("Showing window...")
    window.show()
    print("Window shown")

    print("Starting event loop...")
    app.exec()