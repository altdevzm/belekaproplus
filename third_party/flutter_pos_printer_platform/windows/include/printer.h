#ifndef PRINTER_H_
#define PRINTER_H_

#include <map>
#include <memory>
#include <sstream>
#include <vector>

struct Printer
{
    const std::string name;
    const std::string model;
    const bool isDefault;   // renamed: 'default' is a C++ keyword
    const bool available;

    Printer(std::string name,
            std::string model,
            bool isDefault,
            bool available)
        : name(name),
          model(model),
          isDefault(isDefault),
          available(available) {}
};

class PrintManager
{
public:
    static std::vector<Printer> listPrinters();
    static BOOL pickPrinter(std::string printerName);
    static BOOL printBytes(std::vector<uint8_t> data);
    static BOOL close();

private:
    static HANDLE _hPrinter;
};

#endif
