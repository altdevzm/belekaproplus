# 🏪 Beleka POS

A modern, full-featured Point of Sale system built with Flutter for desktop.

[![Release](https://img.shields.io/github/v/release/altdevzm/beleka-pos?style=flat-square&label=Latest%20Release)](https://github.com/altdevzm/beleka-pos/releases/latest)
[![License](https://img.shields.io/badge/license-proprietary-red?style=flat-square)](LICENSE)

---

## ✨ Features

- 🛒 **Cashier Screen** — Product catalog with category filtering, grid/list view, barcode scanner support
- 📊 **Sales & Reporting** — Daily/monthly sales reports with branded PDF/Excel exports
- 📦 **Inventory Management** — Stock tracking with low-stock alerts
- 👥 **Customer Management** — Customer profiles and purchase history
- 💳 **Multi-payment** — Cash, card, and mobile money support
- 🖨️ **Receipt Printing** — Thermal printer support with store logo & branding
- 🏷️ **Store Branding** — Custom logo, address, contacts, TPIN on all documents
- 🔐 **Role-based Access** — Manager and cashier roles
- 🌙 **Dark Mode** — Modern dark UI with professional design

---

## 📥 Installation

### Windows
1. Go to [Releases](https://github.com/altdevzm/beleka-pos/releases/latest)
2. Download `Beleka_POS_Setup_vX.X.X.exe`
3. Run as Administrator
4. Follow the setup wizard

### Linux
```bash
# Download from Releases page, then:
tar -xzf Beleka_POS_Linux_vX.X.X.tar.gz
chmod +x beleka_pos
./beleka_pos
```

---

## 🚀 Development

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel)
- Windows: Visual Studio 2022 with C++ desktop workload
- Linux: `clang cmake ninja-build pkg-config libgtk-3-dev`

### Getting Started
```bash
git clone https://github.com/altdevzm/beleka-pos.git
cd beleka-pos
flutter pub get
flutter run -d windows   # or linux
```

---

## 📦 Creating a Release

This project uses **GitHub Actions** to automatically build and publish releases.

### Steps to release a new version:
1. Update the version in `pubspec.yaml` (e.g. `version: 1.1.0+2`)
2. Commit and push your changes
3. Create and push a git tag:
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```
4. GitHub Actions will automatically:
   - Build the Windows installer (`.exe`)
   - Build the Linux bundle (`.tar.gz`)
   - Create a GitHub Release with both files attached

---

## 📄 License

Proprietary — © Beleka Technologies. All rights reserved.
