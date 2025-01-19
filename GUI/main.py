from PyQt6.QtWidgets import *
from PyQt6.QtCore import *
from Components import *

from qt_material import apply_stylesheet
import sys
import os

class MainWindow(QMainWindow):
    def __init__(self, inputFile=None):
        super().__init__()
    
        self.setFixedSize(QSize(550, 570))
        self.setWindowTitle("FrameMonkey")

        fileSelectLayout = Components.FileInputComponent()
        videoTimesLayout = Components.VideoComponent()
        checkboxLayout = Components.CheckboxComponent()
        qualityLayout = Components.QualityComponent()
        saveLayout = Components.SaveComponent()

        layout = QVBoxLayout()
        
        layout.addLayout(fileSelectLayout)
        layout.addLayout(videoTimesLayout)
        layout.addLayout(checkboxLayout)
        layout.addLayout(qualityLayout)
        layout.addLayout(saveLayout)

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