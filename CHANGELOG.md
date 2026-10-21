# Changelog

## v0.2.1 — 2026-10-21

Build 14: macOS IPv4 and IPv6 ping invocations verified separately; the external process deadline bounds both.

### Русский

- Сервис обновлений GitHub Releases: сравнение версий, release notes, проверка SHA-256 и установка с перезапуском; переключатель проверки при запуске. Логика проверки изучена в MacPulse в режиме чтения.
- VPN без SSH: внешний туннель задаётся в профиле, ping выполняется с Mac. Убраны автоматические SSH-запуски, known_hosts и Python на ноде, а также предупреждение пробника на карте. Недоступные скорости не подменяются нулями.
- Атомарный `live_snapshot.json` в Application Support, fallback для виджетов при недоступном App Group, выбор более свежего снимка и точечный файловый sandbox entitlement.
- Новый средний Container / VM виджет: состояние, vCPU, RAM, IP, uptime; выбор машины в настройках с привязкой к профилю.
- Установщик одной командой с SHA-256, проверкой бандла, снятием карантина только с приложения, регистрацией виджета и запуском. Homebrew cask и RU/EN инструкции.

### English

- GitHub Releases updater: version comparison, release notes, SHA-256 validation, installation/relaunch and optional startup checks; the reference updater in MacPulse was studied read-only.
- SSH-free VPN: profile-defined external tunnel and Mac-side ping. Removed automatic SSH processes, known_hosts/Python requirements and the probe warning on the map. Unavailable rates are not fabricated.
- Atomic Application Support `live_snapshot.json`, widget fallback when App Group access fails, freshest-snapshot selection and a narrow sandbox file entitlement.
- New medium Container / VM widget with status, vCPU, RAM, IP and uptime; profile-scoped machine selection in Settings.
- One-command installer with SHA-256, bundle validation, app-only quarantine removal, widget registration and launch. Homebrew cask and RU/EN instructions.

The sandbox fallback is verified locally with a signed ad-hoc process without App Group entitlement and a negative control without file access. Compatibility with every other Mac is not claimed; macOS controls WidgetKit refresh scheduling. Downloads remain ad-hoc signed, without Apple notarization.

## v0.2.0 — 2026-10-20

### Русский

Масштабное обновление рабочего пространства ProxPulse: от трёх режимов машин до создания VM/LXC и новой телеметрии.

- **Сетка / Стойка 19″ / Карта** с единым инспектором и действиями. Рэковые лезвия 1U/2U, OLED-датчики и Tx/Rx-светодиоды.
- **Живая сеть и AmneziaWG/WireGuard**: мосты, гостевые IP, runtime-интерфейсы `awg*`/`wg*`/`tun*` через SSH, внешний VPN endpoint, RTT и скорости туннеля.
- **Анимированные потоки** RX/TX на TimelineView + Canvas, с непрерывной фазой при изменении скорости; исправлен запуск частиц при первом показе холста.
- **Drag & Drop всех узлов**, сохранение координат по профилю/ноде, Auto-layout и Recenter. Жёсткие границы карточек и pan — 24 pt; зум сохраняет всю схему видимой.
- **Компактные ↓/↑ бейджи** точно в середине кривых Безье. Нулевой и низкий трафик скрывается, если оба направления ниже 10 B/s.
- **Мастер VM/LXC** с каталогами Proxmox, свободным VMID, проверкой API-параметров, CPU/RAM/диском/сетью и локальными пресетами без паролей.
- **Защита удаления**: машина должна быть остановлена, требуется точный VMID или имя. Подтверждения перезагрузки/остановки и отслеживание задачи Proxmox.
- **Новый стеклянный инспектор**: четыре KPI-плитки, vCPU, RAM, янтарный SWAP, диск, uptime/IP, SSH/веб-консоль и шесть неоновых графиков с наведением.
- **Настройки в сайдбаре**: профили, тест соединения, RU/EN, три темы, пять акцентов, интервалы опроса, пороги диска и уведомления со звуком.
- **Виджеты Small/Medium/Large** следуют активному LIVE/DEMO-профилю: немедленная запись снимка и запрос обновления при переключении, ограниченные фоновые reload-запросы.
- Новая Retina-галерея настоящего интерфейса на DEMO-данных и обновлённая RU/EN документация.

**Установка:** откройте `ProxPulse-v0.2.0.dmg` и перетащите приложение в Applications, заменив предыдущую версию. SHA-256 опубликован рядом. macOS 14+, универсальная сборка Intel + Apple Silicon; ad-hoc подпись без нотарификации.

### English

A major ProxPulse workspace update: three machine views, VM/LXC provisioning and deeper telemetry.

- **Grid / 19-inch Rack / Topology Map**, sharing the inspector and controls. 1U/2U blades, OLED-style meters and Tx/Rx LEDs.
- **Live networking and AmneziaWG/WireGuard**: bridges, guest IPs, SSH runtime detection of `awg*`/`wg*`/`tun*`, public VPN endpoint, RTT and tunnel rates.
- **Animated RX/TX flows** with TimelineView + Canvas and continuous particle phase across speed changes; particles now start on the first canvas presentation.
- **Drag every node**, persist positions per profile/node, reset with Auto-layout and fit with Recenter. Hard 24 pt card/pan boundaries; zoom keeps the full graph visible.
- **Micro ↓/↑ badges** at exact cubic Bezier midpoints. Hide idle/low traffic when both directions are below 10 B/s.
- **VM/LXC wizard** with Proxmox catalogs, next VMID, API parameter review, CPU/RAM/disk/network controls and local password-free presets.
- **Guarded deletion** requires a stopped machine and exact VMID/name. Reboot/stop confirmations and Proxmox task tracking.
- **Redesigned glass inspector**: four KPI tiles, vCPU, RAM, amber SWAP activity, disk, uptime/IP, SSH/web console and six neon charts with hover values.
- **Sidebar settings** for profiles, connection tests, RU/EN, three themes, five accents, polling intervals, disk thresholds and notification sound.
- **Small/Medium/Large widgets** follow the active LIVE/DEMO profile through immediate snapshot writes/reload requests and throttled background reloads.
- New Retina gallery of the actual interface with DEMO data, plus expanded Russian/English documentation.

**Install:** open `ProxPulse-v0.2.0.dmg` and drag the app into Applications, replacing the previous version. A SHA-256 file is included. macOS 14+, universal Intel + Apple Silicon; ad-hoc signed, without notarization.

### Validation and limits / Проверка и ограничения

Swift 6 debug and optimized universal runtime targets, WidgetKit entry points/signatures/entitlements, standalone API fixtures and native UI checks were verified locally. Geometry tests cover 300 camera/zoom cases, 192 node corner cases and native drags of all four node kinds into all four corners. Idle badge hiding, layout persistence/reset, localization/theme changes and widget state transitions are covered. Live checks only read server data; provisioning and deletion use fixtures/DEMO during verification.

Runtime tunnel probing needs SSH key authentication, trusted host keys and Python 3 on the node. Endpoint RTT is outside the VPN. QEMU telemetry depends on API/Guest Agent availability. Charts keep session history; widgets and notifications require the app to run, and macOS controls actual widget redraw timing.

## v0.1.0

Initial public release: native dashboard, activity rings, storage sunburst, profiles and Keychain, VM/LXC controls, desktop widgets, settings, localization and local alerts.
