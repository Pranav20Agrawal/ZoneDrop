# ZoneDrop 📶

**ZoneDrop** is a mobile application built using Flutter that helps students and users map out the network signal strength (4G, 5G, and Wi-Fi) across a college campus or any area. It visualizes signal data on a heatmap, making it easy to identify connectivity dead zones and strong signal areas. This is especially useful for identifying poor network spots in hostels, academic buildings, and public zones, helping users and institutions make better connectivity decisions.

---

## 🚀 Features

- 📍 **Real-Time Location Tracking**: Uses GPS to fetch accurate user location.
- 📡 **Signal Strength Detection**: Reads signal strength from 4G, 5G, and Wi-Fi networks.
- 🧠 **Platform Channels with Native Android**: Communicates with Kotlin code to access low-level Android APIs for precise signal readings.
- 🗺️ **Heatmap Visualization**: Displays collected readings on an interactive map with color-coded signal intensity.
- 🎛️ **Filter Controls**: Users can filter the map view by carrier (e.g., Jio, Airtel) and network type (4G, 5G, WiFi).
- ➕ **Manual and Automatic Submission**: Submit a signal reading manually or enable background mode for continuous automatic data collection.
- 📊 **Analytics and Stats Page**: See total readings, average signal strength, and coverage breakdown.
- ✨ **Smooth & Modern UI**: Built with a custom aesthetic design using Flutter and animated transitions.

---

## 📸 Screenshots

> *(Coming soon – Upload screenshots in a `/screenshots` folder and link here)*

<!-- Example format:
### 🏠 Home Screen
![Home Screen](screenshots/home_screen.png)

### 🔥 Heatmap View
![Heatmap](screenshots/heatmap_view.png)

### ➕ Submit Reading
![Submit Reading](screenshots/submit_reading.png)
-->

---

## 🛠️ Installation

### ✅ Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (ensure it's set up and added to PATH)
- Android Studio or VS Code with Flutter & Dart plugins
- Physical Android device or emulator

### 🔧 Steps

1. **Clone the Repository**
   ```bash
   git clone https://github.com/Pranav20Agrawal/ZoneDrop.git
   cd ZoneDrop/frontend/final_zd
   ```

2. **Get Packages**
   ```bash
   flutter pub get
   ```

3. **Run the App**
   ```bash
   flutter run
   ```

---

## 🧠 Tech Stack

- **Flutter & Dart** – for cross-platform mobile development  
- **Kotlin + Platform Channels** – access Android’s native `TelephonyManager` & `WifiManager`  
- **flutter_map** – open-source alternative to Google Maps  
- **flutter_map_heatmap** – for generating signal strength heatmaps  
- **Geolocator** – for GPS-based location services  
- **FastAPI + PostgreSQL (Upcoming)** – backend for real-time data sync, auth, and analytics dashboard  

---

## 🧾 Folder Structure

```bash
ZoneDrop/
│
├── frontend/
│   └── final_zd/                # Flutter app
│       ├── lib/                 # Dart code (screens, widgets, services)
│       ├── android/             # Native Android Kotlin code
│       ├── assets/              # Images, icons, splash assets
│       └── test/                # Unit/widget tests
│
├── backend/                     # Planned FastAPI + PostgreSQL backend
│
└── README.md
```

---

## 📊 Stats & Analytics Preview

> *(Example UI from the app)*

- **Total Readings**: 150  
- **Average Signal Strength**: -78 dBm  
- **Weak Zones**: 24 (highlighted in red)  
- **Strong Zones**: 42 (highlighted in green)  

---

## 🛣️ Roadmap

| Feature                              | Status        |
|--------------------------------------|---------------|
| Basic MVP with manual reading        | ✅ Done        |
| Heatmap + filtering                  | ✅ Done        |
| Background continuous data logging   | ✅ Done        |
| Analytics & stats screen             | ✅ Done        |
| Native Android plugin (Kotlin)       | ✅ Done        |
| FastAPI backend with PostgreSQL      | 🔄 In Progress |
| Authentication system                | 🔜 Planned     |
| Admin dashboard for data export      | 🔜 Planned     |

---

## 🙋‍♂️ Why This Project?

**ZoneDrop** was inspired by real frustration with poor mobile connectivity in specific college zones like hostel washrooms, staircases, and lecture halls. This app empowers users to crowdsource signal strength data to identify these pain points and visualize them clearly. The goal is to create data-driven transparency and assist both students and institutions in improving connectivity infrastructure.

---

## 🤝 Contributing

Contributions, feedback, and feature suggestions are welcome!  
Please open an issue or submit a pull request.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
