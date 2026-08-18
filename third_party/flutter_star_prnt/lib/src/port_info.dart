/// Contains info of the printer connection
class PortInfo {
  /// MacAdress of printer
  String? macAddress;

  /// Model name of printer
  String? modelName;

  /// Port connection of printer, use this to connect to the printer
  String? portName;

  /// USB Serial number of usb printers
  String? usbSerialNumber;

  PortInfo(dynamic port) {
    if (port.containsKey('macAddress')) {
      macAddress = port['macAddress'];
    }
    if (port.containsKey('modelName')) {
      modelName = port['modelName'];
    }
    if (port.containsKey('portName')) {
      portName = port['portName'];
    }
    if (port.containsKey('USBSerialNumber')) {
      usbSerialNumber = port['USBSerialNumber'];
    }
  }
}
