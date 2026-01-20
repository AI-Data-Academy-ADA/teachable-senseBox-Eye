import processing.serial.*;
import java.nio.*;
import websockets.*;
import java.util.Base64;
import controlP5.*;
import java.util.*;

Serial myPort;
WebsocketServer ws;

// must match Arduino sketch
final int cameraWidth = 96;
final int cameraHeight = 96;
final int cameraBytesPerPixel = 1;
final int bytesPerFrame = cameraWidth * cameraHeight * cameraBytesPerPixel;

// frame sync header (must match Arduino)
final byte[] FRAME_HEADER = {
  (byte)0xAA, (byte)0x55, (byte)0xAA, (byte)0x55
};

PImage myImage;
byte[] frameBuffer = new byte[bytesPerFrame];

int headerIndex = 0;
int frameIndex = 0;
boolean readingFrame = false;

String[] portNames;
ControlP5 cp5;
ScrollableList portsList;
boolean clientConnected = false;

int lastFrameTime = -1;

void setup() {
  size(448, 224);
  pixelDensity(displayDensity());
  frameRate(30);

  cp5 = new ControlP5(this);
  portNames = Serial.list();

  portsList = cp5.addScrollableList("portSelect")
    .setPosition(235, 10)
    .setSize(200, 220)
    .setBarHeight(40)
    .setItemHeight(40)
    .addItems(portNames);
  portsList.close();

  ws = new WebsocketServer(this, 8889, "/");

  myImage = createImage(cameraWidth, cameraHeight, RGB);
  noStroke();
}

void draw() {
  background(240);
  image(myImage, 0, 0, 224, 224);
  drawConnectionStatus();
}

void drawConnectionStatus() {
  fill(0);
  textAlign(RIGHT, CENTER);
  if (!clientConnected) {
    text("Not Connected to TM", 410, 100);
    fill(255, 0, 0);
  } else {
    text("Connected to TM", 410, 100);
    fill(0, 255, 0);
  }
  ellipse(430, 102, 10, 10);
}

void portSelect(int n) {
  String portName = (String) cp5
    .get(ScrollableList.class, "portSelect")
    .getItem(n)
    .get("text");

  try {
    if (myPort != null) myPort.stop();
    myPort = new Serial(this, portName, 9600);
    myPort.clear();
    println("Connected to " + portName);

    // reset parser state on new port
    headerIndex = 0;
    frameIndex = 0;
    readingFrame = false;
  } catch (Exception e) {
    println(e);
  }
}

void serialEvent(Serial myPort) {
  while (myPort.available() > 0) {
    int v = myPort.read();   // 0..255 or -1
    if (v < 0) return;

    byte incoming = (byte)(v & 0xFF);

    // --- HEADER SEARCH ---
    if (!readingFrame) {
      if (incoming == FRAME_HEADER[headerIndex]) {
        headerIndex++;
        if (headerIndex == FRAME_HEADER.length) {
          // header found → start reading frame
          readingFrame = true;
          frameIndex = 0;
          headerIndex = 0;
        }
      } else {
        // IMPORTANT: if this byte could be the start of the header, keep 1
        headerIndex = (incoming == FRAME_HEADER[0]) ? 1 : 0;
      }
    }
    // --- FRAME READ ---
    else {
      frameBuffer[frameIndex++] = incoming;

      if (frameIndex == bytesPerFrame) {
        processFrame();
        readingFrame = false;
      }
    }
  }
}

void processFrame() {
  // Write pixels
  int i = 0;
  for (byte b : frameBuffer) {
    int r = b & 0xFF;
    myImage.pixels[i++] = color(r, r, r);
  }
  myImage.updatePixels();

  // FPS / timing debug
  if (lastFrameTime > 0) {
    println("frame time (ms): " + (millis() - lastFrameTime));
  }
  lastFrameTime = millis();

  // send to websocket
  String encoded = Base64.getEncoder().encodeToString(frameBuffer);
  ws.sendMessage(encoded);
}

void webSocketServerEvent(String msg) {
  if (msg.equals("tm-connected")) clientConnected = true;
}
