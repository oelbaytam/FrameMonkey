from PyQt6.QtWidgets import *
from PyQt6.QtCore import *
from PyQt6.QtMultimedia import *
from PyQt6.QtMultimediaWidgets import *

def openFile():
    fileName, _ = QFileDialog.getOpenFileName(directory = QDir.homePath())
    return fileName
