from PyQt6.QtWidgets import *
from PyQt6.QtCore import *
from PyQt6.QtMultimedia import *
from PyQt6.QtMultimediaWidgets import *
from Functions import openFile

from qt_material import apply_stylesheet
import sys
import os

class MainWindow(QMainWindow):
    def __init__(self, inputFile=None):
        super().__init__()
        # TODO: make video player size scale with main display resolution, so that it can be alot bigger
        # TODO: add resizable main tab
        self.setFixedSize(QSize(1920, 1080))
        self.setWindowTitle("FrameMonkey")

        layout = QGridLayout()

        # Input File Component
        #
        self.fileNameLabel = QLabel(inputFile)
        browseFileBtn = QPushButton("Browse")
        browseFileBtn.clicked.connect(self.handleFileOpen)

        layout.addWidget(self.fileNameLabel, 0, 0, 1, 5)
        layout.addWidget(browseFileBtn, 0, 6)

        # Video Player Component
        #
        currentLabel = QLabel("Current Time")
        currentVidTime = QLineEdit()

        self.player = QMediaPlayer()
        self.videoWidget = QVideoWidget()
        self.player.setVideoOutput(self.videoWidget)
        self.videoWidget.setAspectRatioMode(Qt.AspectRatioMode.KeepAspectRatio)

        # Add play/pause button
        self.playButton = QPushButton("Play/Pause")
        self.playButton.clicked.connect(self.togglePlayback)

        startLabel = QLabel("Start Time")
        startTimeTrim = QLineEdit()
        stopLabel = QLabel("Stop Time")
        stopTimeTrim = QLineEdit()

        layout.addWidget(self.videoWidget, 1, 0, 4, 7)
        # Move play button below video widget
        layout.addWidget(self.playButton, 5, 3)  # Changed from 2,3 to 5,3

        layout.addWidget(currentLabel, 2, 0)
        layout.addWidget(startLabel, 2, 1)
        layout.addWidget(stopLabel, 2, 2)

        layout.addWidget(currentVidTime, 3, 0)
        layout.addWidget(startTimeTrim, 3, 1)
        layout.addWidget(stopTimeTrim, 3, 2)

        # Checkbox Component
        #
        trimVideo = QCheckBox()
        trimVideoLabel = QLabel("Trim Video")
        twoPass = QCheckBox()
        twoPassLabel = QLabel("Encode Two Passes")
        hwAccel = QCheckBox()
        hwAccel.setChecked(True)
        hwAccelLabel = QLabel("Enable Hardware Acceleration (Default)")

        layout.addWidget(trimVideo, 4, 0)
        layout.addWidget(trimVideoLabel, 4, 1)

        layout.addWidget(twoPass, 5, 0)
        layout.addWidget(twoPassLabel, 5, 1)

        layout.addWidget(hwAccel, 6, 0)
        layout.addWidget(hwAccelLabel, 6, 1)

        # Quality Select Component
        #
        sizeLabel = QLabel("Size")
        fileSize = QLineEdit("10")
        MBLabel = QLabel("MB")

        # Disable the size-related widgets
        sizeLabel.setEnabled(False)
        fileSize.setEnabled(False)
        MBLabel.setEnabled(False)

        qualityLabel = QLabel("Quality")
        encodingSpeed = QLineEdit("6")  # Set default value to 6
        qinfoLabel = QLabel("1-Faster, 6-Slower (6 Default)")

        layout.addWidget(sizeLabel, 7, 0)
        layout.addWidget(fileSize, 7, 1)
        layout.addWidget(MBLabel, 7, 2)

        layout.addWidget(qualityLabel, 8, 0)
        layout.addWidget(encodingSpeed, 8, 1)
        layout.addWidget(qinfoLabel, 8, 2)

        # File Save Component
        #
        saveFileName = QLineEdit(inputFile)
        saveBtn = QPushButton("Save")

        layout.addWidget(saveFileName, 9, 0, 1, 5)
        layout.addWidget(saveBtn, 9, 6)

        # Error handling
        self.player.errorOccurred.connect(self.handleError)

        # Container setup
        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)

    def handleFileOpen(self):
        fileName = openFile()
        if fileName:
            self.fileNameLabel.setText(fileName)
            self.player.setSource(QUrl.fromLocalFile(fileName))
            self.player.play()

    def togglePlayback(self):
        if self.player.playbackState() == QMediaPlayer.PlaybackState.PlayingState:
            self.player.pause()
        else:
            self.player.play()

    def handleError(self, error, errorString):
        if error != QMediaPlayer.Error.NoError:
            QMessageBox.warning(self, "Media Error", f"Error playing media: {errorString}")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    apply_stylesheet(app, theme='dark_yellow.xml')
    window = MainWindow(inputFile=os.getcwd())
    window.show()
    app.exec()