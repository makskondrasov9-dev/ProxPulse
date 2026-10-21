# ProxPulse v0.2.2 — Independent Widgets, Topology Zoom & Quick Search

Universal macOS 14+ · Apple Silicon + Intel · Swift 6 · build 16

## Русский

- **Независимые AppIntent-виджеты машин.** Для каждого экземпляра: правый клик → **Изменить виджет → Машина**. Список заново читает кэш активного сервера, автоматически подхватывает новые CT/VM и показывает 🟢 Работает / ⚪️ Остановлен. При удалении выбранной машины появляется «Машина не найдена».
- **Обзор с картой на всю доступную высоту.** Кольца ноды сверху, интерактивная топология под ними, диагностика снизу. Хранилища перенесены в собственный раздел; каталог машин содержит только **Сетку / Стойку**, сортировку RAM/CPU/VMID/имя и фильтры состояния.
- **Навигация мышью.** Плавающие **+ / − / 100% / По размеру / В центр**, колесо мыши с зумом относительно курсора и жесты трекпада.
- **Фильтры на карте:** **Все / Работают / Выключены**, с плавным исчезновением карточек и их связей.
- **Стабильная расстановка.** Координаты узлов сохраняются относительно центра графа отдельно для профиля/ноды; прежняя расстановка мигрирует автоматически. Жёсткий барьер перетаскивания — 24 pt. При увеличении схему можно просматривать панорамированием; ограничение камеры предотвращает уход в пустоту. Кривые и бейджи следуют за узлами при зуме и ресайзе.
- **Быстрый поиск ⌘K.** Кликабельная строка в шапке, поиск по имени, VMID и IP, быстрый инспектор, SSH и Start/Reboot; Esc или клик снаружи закрывает меню. Перезагрузка сохраняет подтверждение.
- **Встроенная проверка обновлений.** Настройки → Обновления: changelog, проверка версии, SHA-256 и установка с перезапуском; проверка при запуске настраивается.

После обновления старый статический виджет машины может потребовать удаления и повторного добавления: он не содержит AppIntent-конфигурации. Для каждого нового виджета выберите свою машину. Фактическое расписание обновления виджетов определяет macOS.

## English

- **Independent AppIntent machine widgets.** Right-click each widget → **Edit Widget → Machine**. Each instance has its own selection. The picker rereads the active server cache, includes newly created CT/VM workloads, and shows 🟢 Running / ⚪️ Stopped. Deleted selections display “Machine not found”.
- **Full-height Overview topology.** Node activity rings above the map, diagnostics below. Storage has its own section; **Machines** contains only Grid/Rack, RAM/CPU/VMID/name sorting and status filters.
- **Mouse navigation.** Floating **+ / − / 100% / Fit to window / Recenter** controls, cursor-anchored mouse-wheel zoom and trackpad gestures.
- **Map filters:** **All / Running / Stopped**, with animated removal of matching nodes and links.
- **Stable layout.** Profile/node-scoped coordinates are stored relative to the graph center; existing layouts migrate automatically. Node dragging has a hard 24 pt boundary. Zoomed content can be explored with pan; camera bounds prevent moving the graph into empty space. Curves and badges track nodes during zoom and resize.
- **Quick Search ⌘K.** Click the header capsule or press ⌘K, search by name, VMID or IP, then open the inspector/SSH or Start/Reboot. Esc or an outside click dismisses it. Reboots retain confirmation.
- **Built-in update checks.** Settings → Updates includes release notes, version comparison, SHA-256 verification and installation/relaunch, with optional startup checks.

An existing static machine widget may need to be removed and added again after updating because it has no AppIntent configuration. Choose a machine separately for each new widget. macOS controls actual widget refresh scheduling.

## Install / Установка

```sh
curl -fsSL https://raw.githubusercontent.com/makskondrasov9-dev/ProxPulse/main/scripts/install.sh | bash
```

The installer downloads the latest stable DMG and verifies its SHA-256, installs to `/Applications`, removes quarantine only from `ProxPulse.app`, registers WidgetKit and launches the app.

Manual installation: open the DMG and drag ProxPulse to Applications. If macOS blocks the trusted download:

```sh
xattr -cr /Applications/ProxPulse.app
```

Distribution is ad-hoc signed, without Apple notarization. Credentials remain in Keychain; releases contain no personal profiles. SHA-256 is attached alongside the DMG.

## SHA-256

```text
33c24ef68c73d20c2f960d782939a0d5b04458bfd544add90d1620b9269d2158  ProxPulse-v0.2.2.dmg
```
