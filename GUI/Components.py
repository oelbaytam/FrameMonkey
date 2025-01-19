from PyQt6.QtWidgets import *
from PyQt6.QtCore import *
from PyQt6.QtMultimedia import *
from PyQt6.QtMultimediaWidgets import *

def openFile():
    fileName, _ = QFileDialog.getOpenFileName(directory = QDir.homePath())
    
    return fileName


class Components():
    def VideoComponent(fileDirectory=None):

        currentLabel = QLabel("Current Time")
        currentVidTime = QLineEdit()
        
        player = QMediaPlayer()
        player.setSource(QUrl.fromLocalFile(fileDirectory))
        videoWidget = QVideoWidget()
        videoWidget.setAspectRatioMode(Qt.AspectRatioMode.KeepAspectRatio)
        player.setVideoOutput(videoWidget)
        player.play()

        startLabel = QLabel("Start Time")
        startTimeTrim = QLineEdit()
        stopLabel = QLabel("Stop Time")
        stopTimeTrim = QLineEdit()

        labelLayout = QHBoxLayout()
        labelLayout.addWidget(currentLabel)
        labelLayout.addWidget(startLabel)
        labelLayout.addWidget(stopLabel)

        videoTimesLayout = QHBoxLayout()
        videoTimesLayout.addWidget(currentVidTime)
        videoTimesLayout.addWidget(startTimeTrim)
        videoTimesLayout.addWidget(stopTimeTrim)

        layout = QVBoxLayout()
        layout.addWidget(videoWidget)
        layout.addLayout(labelLayout)
        layout.addLayout(videoTimesLayout)

        return layout
    
    def FileInputComponent(inputFile=None):
        fileName = QLabel(inputFile)
        browseFile = QPushButton("Browse")

        fileDirectory = browseFile.clicked.connect(openFile)
        fileName.setText = fileDirectory

        layout = QHBoxLayout()
        layout.addWidget(fileName)
        layout.addWidget(browseFile)

        return layout
    
    def CheckboxComponent():
        trimVideo = QCheckBox()
        trimVideoLabel = QLabel("Trim Video")
        twoPass = QCheckBox()
        twoPassLabel = QLabel("Encode Two Passes")
        hwAccel = QCheckBox()
        hwAccelLabel = QLabel("Enable Hardware Acceleration")
        layout = QGridLayout()

        layout.addWidget(trimVideo, 0, 0)
        layout.addWidget(trimVideoLabel, 0, 1)

        layout.addWidget(twoPass, 1, 0)
        layout.addWidget(twoPassLabel, 1, 1)

        layout.addWidget(hwAccel, 2, 0)
        layout.addWidget(hwAccelLabel, 2, 1)

        return layout
    
    def QualityComponent():

        sizeLabel = QLabel("Size")
        fileSize = QLineEdit()
        MBLabel = QLabel("MB")

        qualityLabel = QLabel("Quality")
        encodingSpeed = QLineEdit()
        qinfoLabel = QLabel("1-Fast & poor, 6-Slow & good")

        layout = QGridLayout()
        layout.addWidget(sizeLabel, 0, 0)
        layout.addWidget(fileSize, 0, 1)
        layout.addWidget(MBLabel, 0, 2)

        layout.addWidget(qualityLabel, 1, 0)
        layout.addWidget(encodingSpeed, 1, 1)
        layout.addWidget(qinfoLabel, 1, 2)

        return layout
    
    def SaveComponent(filename=None):
        fileName = QLineEdit(filename)
        saveBtn = QPushButton("Save")

        layout = QHBoxLayout()
        layout.addWidget(fileName)
        layout.addWidget(saveBtn)

        return layout