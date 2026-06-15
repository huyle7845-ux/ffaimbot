=== FFAimbot - FreeFire MAX aimbot v2.123.1 ===
Author: seraph

=== Cấu trúc thư mục ===
FFAimbotTweak/
├── .github/workflows/build.yml  # GitHub Actions CI (build trên macOS cloud)
├── Makefile          # Theos build file
├── control           # Package metadata
├── FFAimbot.plist    # Bundle filter
├── Tweak.xm          # Source code aimbot
├── inject_ipa.sh     # Script inject vào IPA (macOS)
├── inject_windows.py # Script inject dylib vào binary (Windows)
├── README.txt        # File này

=== CÁCH 1: Build trên Windows (dùng GitHub Actions FREE) ===
Không cần macOS. Tất cả làm trên Windows.

Bước 1: Push lên GitHub
  - Tạo repo mới trên GitHub
  - Push code vào repo:
    git init
    git add .
    git commit -m "initial"
    git remote add origin https://github.com/YOUR_USER/ffaimbot.git
    git push -u origin main

Bước 2: GitHub Actions tự động build
  - Vào GitHub → Repo → Actions tab
  - Chọn workflow "Build FFAimbot dylib"
  - Click "Run workflow"
  - Đợi ~5-10 phút, build xong sẽ có artifact download

Bước 3: Download artifact
  - GitHub Actions → Artifacts → Download FFAimbot.zip
  - Giải nén, lấy file FFAimbot.dylib (trong thư mục dylib/)

Bước 4: Inject dylib vào IPA (trên Windows)
  Yêu cầu: Python 3.6+ + 7-Zip

  a) Giải nén IPA:
     7z x FreeFireMax.ipa -oextracted/

  b) Copy dylib vào Frameworks:
     copy FFAimbot.dylib extracted/Payload/FreeFireMAX.app/Frameworks/
     copy libsubstrate.dylib extracted/Payload/FreeFireMAX.app/Frameworks/

     (libsubstrate.dylib tải từ:
      https://github.com/DaveCTaylor/Substrate/releases)

  c) Inject load command vào binary:
     python inject_windows.py "extracted/Payload/FreeFireMAX.app/FreeFireMAX" libsubstrate.dylib
     python inject_windows.py "extracted/Payload/FreeFireMAX.app/FreeFireMAX" FFAimbot.dylib

  d) Nén lại thành IPA:
     cd extracted
     7z a -tzip ../FreeFireMax_modded.ipa Payload/

Bước 5: Cài đặt lên iPhone
  - Cắm iPhone vào Windows
  - Mở Sideloadly (https://sideloadly.io/)
  - Kéo file FreeFireMax_modded.ipa vào
  - Nhập Apple ID (cần free developer account)
  - Click "Start" → nhập mật khẩu app-specific
  - Đợi sideload xong, vào Settings → General → VPN & Device Management
  - Trust certificate
  - Mở game và chơi

=== CÁCH 2: Build trực tiếp trên macOS (có Theos) ===

Bước 1: Thiết lập Theos
  $ export THEOS=/path/to/theos
  $ $THEOS/bin/nic.pl

Bước 2: Build tweak
  $ cd FFAimbotTweak
  $ make package
  # Output: packages/FFAimbot.deb

Bước 3: Inject vào IPA
  $ chmod +x inject_ipa.sh
  $ ./inject_ipa.sh /path/to/FreeFireMax.ipa
  # Output: FreeFireMax_modded.ipa

Bước 4: Cài đặt
  - Jailbreak: scp .deb → iPhone → dpkg -i
  - Sideload: dùng Sideloadly với .ipa đã mod
  - TrollStore: mở .ipa bằng TrollStore

=== CÁCH 3: Dùng TrollStore (iOS 14-16.6.1) ===
- Không cần jailbreak, không cần sign
- Chỉ cần .ipa đã mod sẵn
- Mở TrollStore → Install → chọn .ipa

=== Thông số kỹ thuật ===
- Game: FreeFire MAX v2.123.1 (com.dts.freefiremax)
- Unity: 2022.3.47f1, il2cpp metadata v31
- CodeRegistration: 0xAA8E1E8
- MetadataRegistration: 0xAC39948

=== RVA Offsets ===
Camera.get_main              : 0x8599008
Camera.WorldToScreenPoint    : 0x8598914
Camera.ScreenToWorldPoint    : 0x8598A70
Transform.get_position       : 0x8605018
Transform.get_rotation       : 0x8605308
Transform.set_eulerAngles    : 0x8605368
GameObject.FindWithTag       : 0x85F6D1C
Object.FindObjectsOfType     : 0x85FD2C4
GetFireDirection             : 0x407AD3C
WorldToScreenPoint (eye)     : 0x8598514

=== Lưu ý quan trọng ===
1. DataDome anti-cheat: Game có DataDome, cần bypass trước khi inject
   - Method: hook NSURLProtocol / disable DataDome initialization
   - Hoặc patch binary để skip DataDome

2. Re-sign: Apple developer account FREE cũng được (7 ngày hết hạn)
   - Dùng Sideloadly tự động re-sign mỗi 7 ngày

3. iOS version: Cần jailbreak hoặc TrollStore để injected dylib hoạt động
   - Sideloadly + free account: dylib injection hoạt động nhưng limited

4. Update game: Khi game update, cần dump lại metadata và update RVA offsets
