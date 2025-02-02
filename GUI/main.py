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
    
        self.setFixedSize(QSize(550, 570))
        self.setWindowTitle("FrameMonkey")

        layout = QGridLayout()

        # Input File Component
        #
        
        fileNameLabel = QLabel(inputFile)
        browseFileBtn = QPushButton("Browse")

        browseFileBtn.clicked.connect(openFile)

        layout.addWidget(fileNameLabel, 0, 0, 0, 5)
        layout.addWidget(browseFileBtn, 0, 6)

        # Video Player Component
        #
        currentLabel = QLabel("Current Time")
        currentVidTime = QLineEdit()
        
        player = QMediaPlayer()
        player.setSource(QUrl.fromLocalFile(inputFile))
        videoWidget = QVideoWidget()
        videoWidget.setAspectRatioMode(Qt.AspectRatioMode.KeepAspectRatio)
        player.setVideoOutput(videoWidget)
        player.play()

        startLabel = QLabel("Start Time")
        startTimeTrim = QLineEdit() 
        stopLabel = QLabel("Stop Time")
        stopTimeTrim = QLineEdit()

        layout.addWidget(videoWidget, 1, 0, 8, 7)
        layout.addWidget(currentLabel, 2, 0)
        layout.addWidget(startLabel, 2, 1)
        layout.addWidget(stopLabel, 2, 2)

        layout.addWidget(currentVidTime, 3, 0)        
        layout.addWidget(startTimeTrim, 3, 1)
        layout.addWidget(stopTimeTrim, 3 , 2)

        # Checkbox Component
        #

        trimVideo = QCheckBox()
        trimVideoLabel = QLabel("Trim Video")
        twoPass = QCheckBox()
        twoPassLabel = QLabel("Encode Two Passes")
        hwAccel = QCheckBox()
        hwAccelLabel = QLabel("Enable Hardware Acceleration")

        layout.addWidget(trimVideo, 4, 0)
        layout.addWidget(trimVideoLabel, 4, 1)

        layout.addWidget(twoPass, 5, 0)
        layout.addWidget(twoPassLabel, 5, 1)

        layout.addWidget(hwAccel, 6, 0)
        layout.addWidget(hwAccelLabel, 6, 1)

        # Quality Select Component
        #

        sizeLabel = QLabel("Size")
        fileSize = QLineEdit()
        MBLabel = QLabel("MB")

        qualityLabel = QLabel("Quality")
        encodingSpeed = QLineEdit()
        qinfoLabel = QLabel("1-Fast & poor, 6-Slow & good")

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

        layout.addWidget(saveFileName, 9, 0, 9, 5)
        layout.addWidget(saveBtn, 9, 6)

        # End of Components
        #

        container = QWidget()
        container.setLayout(layout)

        self.setCentralWidget(container)


if __name__ == "__main__":
    app = QApplication(sys.argv)

    #apply material stylesheet
    apply_stylesheet(app, theme='dark_yellow.xml')

    window = MainWindow(inputFile=os.getcwd())
    window.show()
    
    app.exec()