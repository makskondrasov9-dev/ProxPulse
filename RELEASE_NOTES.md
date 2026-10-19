# ProxPulse v0.1.0

Первый публичный релиз / First public release.

**macOS 14+ · Universal: Apple Silicon + Intel · Swift 6**

## Русский

Нативный клиент Proxmox VE: анимированные кольца активности, интерактивный дисковый радар, меню-бар и три размера виджетов рабочего стола. Карточки и инспектор VM/LXC показывают CPU/vCPU, RAM, SWAP, диск и скорости сети. Доступны управление машинами с подтверждением, диагностика, Keychain, RU/EN, темы и пять акцентов.

Виджеты следуют выбранному профилю DEMO/LIVE. При смене источника и первом ответе LIVE таймлайн запрашивается сразу; фактическое расписание контролирует macOS.

**Установка:** откройте `ProxPulse-v0.1.dmg`, перетащите приложение в Applications и запустите его оттуда. Затем добавьте виджеты через системную галерею.

Релиз подписан ad-hoc и не нотарифицирован Apple. На первом запуске может потребоваться «Всё равно открыть» в настройках конфиденциальности и безопасности. При замене прежней ad-hoc сборки может появиться повторный системный запрос доступа к Keychain. Секреты сервера вводятся в приложении и сохраняются в Apple Keychain. Конфигурация разработчика и live-данные в дистрибутив не включены.

## English

A native Proxmox VE client with animated activity rings, an interactive storage sunburst, a menu-bar overview and three desktop widget sizes. Inspect VM/LXC CPU/vCPU, RAM, SWAP, disk and network rates; manage machines with confirmation, diagnose incidents, and customize RU/EN, themes and accents.

Widgets follow the selected DEMO/LIVE profile. Source changes and the first LIVE response request an immediate timeline reload; macOS controls actual scheduling.

**Install:** open `ProxPulse-v0.1.dmg`, drag the app to Applications and launch it there. Add desktop widgets from the system gallery.

This release is ad-hoc signed and is not notarized by Apple. First launch may require Open Anyway in Privacy & Security. Replacing an earlier ad-hoc build may prompt for Keychain access again. Server secrets are entered in the app and stored in Apple Keychain. Developer profiles and live data are not included.

The attached SHA-256 file can be verified with `shasum -a 256 -c ProxPulse-v0.1.dmg.sha256`.


## Validation / Проверки

- Swift 6 optimized builds for x86_64 and arm64; universal app and WidgetKit extension.
- API/core regression checks and native SwiftUI RU/EN, theme and widget renders passed.
- App and extension signatures, shared App Group and widget sandbox entitlements verified.
- Compressed DMG checksum and mounting verified; app copied from the image to Applications and launched on macOS 14.8.9 (Intel).
- ARM64 was cross-compiled and structurally verified; Apple Silicon hardware execution was not available on this build machine.
