# Exporting Deepfake Software to .exe

This guide explains how to build and package your Flutter desktop application for Windows.

## 1. Pre-build Checklist

### Update API URL
Before building for production, ensure your application is pointing to the live server instead of `localhost`.

1. Open `lib/services/api_service.dart`.
2. Locate the `kBaseUrl` variable.
3. Uncomment the production URL and comment out the local one:
   ```dart
   // const String kBaseUrl = 'http://127.0.0.1:8000/api/v1'; // Local
   const String kBaseUrl = 'https://deepfakessoftwares.com/api/v1'; // Production
   ```

## 2. Generate the Executable (.exe)

Run the following command in your terminal:

```powershell
flutter build windows
```

### Where to find the output?
Once the build completes, your executable and its required dependencies will be located at:
`build\windows\x64\runner\Release\`

> [!IMPORTANT]
> To share the app, you must zip the **entire** `Release` folder. 
> 
> **Why did I see the "flutter_windows.dll not found" error?**
> You likely only copied the `RealFaceAI.exe` file. On Windows, Flutter apps are not "self-contained" in a single file by default. They depend on:
> 1. `flutter_windows.dll` (The engine)
> 2. `data\` folder (Your assets and code)
> 3. Other `.dll` files in the same folder.
> 
> To fix this, you must share the whole folder or create an **Installer** (see section 3 below).

## 3. Create a Single-File Installer (Recommended)

To create a professional `.msix` installer (which users can double-click to install like a regular Windows app), follow these steps:

### Step A: Add the MSIX package
Run this command to add the distribution tool:
```powershell
flutter pub add dev:msix
```

### Step B: Configure pubspec.yaml (Optional)
Add this configuration to the end of your `pubspec.yaml` to customize the installer:
```yaml
msix_config:
  display_name: RealFaceAI
  publisher_display_name: Timzona Timothy
  identity_name: app.realfaceai.desktop
  msix_version: 1.0.0.0
  logo_path: windows\runner\resources\app_icon.ico
```

### Step C: Build the Installer
Run the following command:
```powershell
flutter pub run msix:create
```

Your installer will be generated in `build\windows\x64\runner\Release\`.

---

## Troubleshooting
- **Visual Studio missing**: Ensure you have "Desktop development with C++" installed via the Visual Studio Installer.
- **Icons**: To change the app icon, replace `windows\runner\resources\app_icon.ico`.
- **"Windows protected your PC" (SmartScreen)**: This happens because the app isn't digitally signed with a trusted certificate. 
  - **For Testing**: Click **"More info"** -> **"Run anyway"**.
  - **For Production**: You would need to buy a Code Signing Certificate (EV or Standard) from a provider like DigiCert or Sectigo, which is quite expensive ($300+/year).




<!-- using inno best  -->
# 1. Build Flutter release
flutter build windows --release

flutter pub run msix:create

# 2. Compile the installer (adjust path to ISCC.exe)
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss

# 3. Output is at: installer_output/RealFaceAI-Setup-1.0.2.exe (~25MB)
# Upload THIS file to your server's downloads/ folder