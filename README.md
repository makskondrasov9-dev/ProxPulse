<p align="center">
  <img src="Resources/AppIcon-1024.png" width="150" alt="ProxPulse icon" />
</p>
<h1 align="center">ProxPulse</h1>
<p align="center">Your Proxmox cluster. One calm glance.<br/>Ваш кластер Proxmox. Один спокойный взгляд.</p>
<p align="center">
  <a href="https://github.com/makskondrasov9-dev/ProxPulse/releases/tag/v0.1.0">Download v0.1.0</a> ·
  macOS 14+ · Universal (Apple Silicon & Intel) · Swift 6
</p>

[Русский](#русский) · [English](#english)

## Русский

**ProxPulse** — нативный клиент Proxmox VE для macOS на SwiftUI и WidgetKit. Мониторинг кластера, телеметрия машин и управление ресурсами в одном стеклянном интерфейсе.

![ProxPulse dashboard — demo data](docs/images/dashboard.png)

### Возможности

- **Кольца активности** CPU, RAM и диска: градиенты, плавное заполнение и смена акцентов.
- **Дисковый радар**: интерактивный sunburst в духе DaisyDisk, фокус на секторах и навигация по иерархии.
- **Виджеты рабочего стола** Small / Medium / Large следуют активному профилю приложения — DEMO или LIVE.
- **Инспектор машин**: vCPU, RAM, SWAP, диск, скорости сети, uptime, IP и шесть графиков.
- **VM и LXC**: Start, Reboot, Shutdown и Stop; подтверждение остановки и ожидание результата задачи Proxmox.
- **Меню-бар**, быстрый переход в Terminal.app и веб-консоль.
- **Диагностика** по доступным журналам и метрикам: OOM, заполнение дисков, службы, сеть; без ИИ и выдуманных причин.
- **RU / EN**, системная/тёмная/светлая тема, пять акцентов, опрос 2 / 4 / 10 секунд и уведомления с настраиваемым порогом диска.
- Несколько серверных профилей; API Token или логин/пароль. Секреты хранятся в **Apple Keychain**.

### Установка из DMG

1. Скачайте **[ProxPulse-v0.1.dmg](https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.1.0/ProxPulse-v0.1.dmg)** со страницы релиза.
2. Откройте образ и перетащите **ProxPulse.app → Applications**.
3. Запустите `/Applications/ProxPulse.app`. Выберите DEMO или добавьте свой сервер в WORKSPACE / Настройках.
4. Для виджетов: правый клик на рабочем столе → **Изменить виджеты** → найдите **ProxPulse**. Приложение должно быть запущено для получения свежих метрик.

Первый релиз подписан **ad-hoc**, без Developer ID и нотарификации Apple. Если macOS блокирует первый запуск, после попытки открытия используйте **Системные настройки → Конфиденциальность и безопасность → Всё равно открыть**, только если доверяете скачанному релизу. [Инструкция Apple](https://support.apple.com/102445). Отключать Gatekeeper не требуется.

При замене прежней ad-hoc сборки macOS может повторно запросить доступ к сохранённым данным Keychain. Подтвердите его только в системном диалоге.

Требования: macOS 14 Sonoma или новее; Intel или Apple Silicon. Для живого мониторинга нужен HTTPS-доступ к Proxmox VE и права чтения ресурсов; управление машинами требует соответствующих прав Proxmox. Для локальных сертификатов можно разрешить самоподписанный SSL в профиле.

### Данные и ограничения

- Пароли и API Secret не сохраняются в репозитории, UserDefaults или кеше виджетов. Метаданные профилей хранятся в Application Support, секреты — в Keychain.
- Виджеты читают UserDefaults и атомарный снимок App Group `group.proxpulsedata`. Смена источника и первый LIVE-ответ сразу вызывают обновление таймлайна; фоновый запрос ограничен 20 секундами. Фактическое расписание отображения контролирует [WidgetKit](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).
- Графики машин накапливаются за текущую сессию. Неизвестные метрики показаны прочерками. QEMU может не возвращать SWAP/занятое место внутри ОС; для IP VM нужен QEMU Guest Agent.
- Радар показывает логические хранилища Proxmox. Общий backing pool может учитываться несколько раз; автоматическое определение размещения дисков гостей пока не реализовано для LIVE.
- Уведомления локальные, работают при запущенном приложении. Команды диагностики не выполняются автоматически.

## English

**ProxPulse** is a native Proxmox VE client for macOS, built with SwiftUI and WidgetKit. Monitor your cluster, inspect machine telemetry and manage VM/LXC workloads in a clean glass interface.

### Features

- Animated **activity rings** for CPU, RAM and disk.
- A **DaisyDisk-style storage sunburst** with sector focus and breadcrumb navigation.
- **Small, Medium and Large desktop widgets** synchronized with the active DEMO/LIVE profile.
- **Machine inspector** with vCPU, RAM, SWAP, disk usage, network rates, uptime, IP addresses and six charts.
- Start, Reboot, Shutdown and Stop, with confirmation for disruptive actions and Proxmox task completion tracking.
- Menu-bar overview, Terminal.app integration and web console access.
- Deterministic diagnostics using available logs and metrics, without AI-generated causes.
- Instant **Russian / English**, Auto / Dark / Light themes, five accents, 2 / 4 / 10-second polling and configurable local alerts.
- Multiple server profiles, API tokens or password authentication, with secrets in **Apple Keychain**.

![Machine inspector — demo data](docs/images/inspector.png)

### Install

1. Download **[ProxPulse-v0.1.dmg](https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.1.0/ProxPulse-v0.1.dmg)** from the release page.
2. Open the disk image and drag **ProxPulse.app → Applications**.
3. Launch `/Applications/ProxPulse.app`. Try DEMO or add your Proxmox server in WORKSPACE / Settings.
4. Right-click the desktop → **Edit Widgets** → search for **ProxPulse**. Keep the app running for fresh metrics.

This first release is **ad-hoc signed**, without an Apple Developer ID or notarization. If macOS blocks the first launch, and you trust the downloaded release, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. See [Apple's instructions](https://support.apple.com/en-us/102445). You do not need to disable Gatekeeper.

Replacing an earlier ad-hoc build may prompt macOS to request access to saved Keychain credentials again. Confirm access in the system dialog.

Requires **macOS 14+**, Apple Silicon or Intel, HTTPS access to Proxmox VE and appropriate Proxmox permissions. Self-signed TLS can be enabled per server profile.

### Data and limitations

Credentials remain in Keychain. Profile metadata is stored in Application Support; the widget App Group contains metrics without credentials. Widgets read the latest shared snapshot on every timeline request; source changes and the first LIVE response request an immediate reload, with background reload requests every 20 seconds. macOS controls actual widget refresh timing.

Machine charts accumulate during the current session. Unavailable metrics display a dash. QEMU guest SWAP/filesystem usage may be unavailable, and VM IP addresses require QEMU Guest Agent. The storage radar reports logical pools, which may share physical capacity. Live guest-to-storage placement is not inferred. Notifications require the app to remain running.

## Build from source / Сборка

Requires Swift 6 and the macOS SDK (Xcode 16+ or compatible Command Line Tools). There are no third-party runtime dependencies.

```sh
git clone https://github.com/makskondrasov9-dev/ProxPulse.git
cd ProxPulse
./scripts/verify-local.sh       # Build, API fixtures, core/UI checks, WidgetKit
./scripts/build-release.sh      # Optimized x86_64 + arm64 app and extension
./scripts/create-dmg.sh         # dist/ProxPulse-v0.1.dmg + SHA-256
```

The compatibility helper only adjusts local files under `.build` when necessary; it does not modify the SDK. The icon is generated with CoreGraphics by `scripts/make-icon.swift`, then compiled with `iconutil`. The release script signs the extension and app with the shared App Group entitlements.

Alternatively open **ProxPulse.xcodeproj** and select the **ProxPulse** scheme. `project.yml` is the XcodeGen source. For distribution with Developer ID, configure your own Team and registered App Group and notarize the app.

```text
Sources/ProxPulseCore       API actor, models, Keychain, diagnostics, shared widget state
Sources/ProxPulse           SwiftUI app, dashboard, inspector, settings, notifications
Sources/ProxPulseWidgetUI   Widget views and timeline provider
WidgetExtension            WidgetKit entry point
Resources                  Original CoreGraphics icon and complete iconset
scripts                    Build, verification, packaging and installation
```

MacPulse was consulted read-only for MenuBarExtra / WidgetKit architecture. ProxPulse's interface and artwork are original. ProxPulse is an independent project and is not affiliated with Proxmox Server Solutions or DaisyDisk.
