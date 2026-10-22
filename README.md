<p align="center">
  <img src="Resources/AppIcon-1024.png" width="140" alt="ProxPulse icon" />
</p>
<h1 align="center">ProxPulse</h1>
<p align="center">Your Proxmox cluster. One calm glance.<br/>Ваш кластер Proxmox. Один спокойный взгляд.</p>
<p align="center">
  <a href="https://github.com/makskondrasov9-dev/ProxPulse/releases/tag/v0.2.3">Release v0.2.3</a> ·
  <a href="https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.3/ProxPulse-v0.2.3.dmg">Download DMG</a> ·
  macOS 14+ · Apple Silicon & Intel · Swift 6
</p>

[Русский](#русский) · [English](#english) · [Changelog](CHANGELOG.md)

## Quick install / Быстрая установка

```sh
curl -fsSL https://raw.githubusercontent.com/makskondrasov9-dev/ProxPulse/main/scripts/install.sh | bash
```

The script verifies the release SHA-256, installs to Applications, removes quarantine **only from ProxPulse.app**, registers its widget and launches the app. / Скрипт сверяет SHA-256, устанавливает приложение, снимает карантин **только с ProxPulse.app**, регистрирует виджет и запускает приложение.

## Gallery / Галерея

Retina screenshots of the actual app with **DEMO data**. Network addresses and workloads shown here are examples.
Снимки настоящего интерфейса с **демо-данными**: адреса и машины служат примерами.

<table>
  <tr>
    <td width="50%"><img src="docs/images/topology.png" alt="Topology Map — AmneziaWG/VPS, network bridges, animated traffic and midpoint speed badges" /><br/><strong>Topology Map / Карта сети</strong></td>
    <td width="50%"><img src="docs/images/rack.png" alt="19-inch server rack — VM and LXC blades with status LEDs and CPU/RAM displays" /><br/><strong>19-inch Rack / Фронтальная стойка</strong></td>
  </tr>
  <tr>
    <td><img src="docs/images/grid.png" alt="Machine catalog — Grid cards, status filters and sorting" /><br/><strong>Machine Grid / Сетка машин</strong></td>
    <td><img src="docs/images/inspector.png" alt="Machine inspector — glass KPI tiles, amber SWAP indicator, actions and neon history charts" /><br/><strong>Machine Inspector / Инспектор машины</strong></td>
  </tr>
</table>

<img src="docs/images/machine-widget.png" width="360" alt="Container / VM widget — selected machine status, vCPU, RAM, IP and uptime (DEMO)" />

## Русский

**ProxPulse** — нативный клиент Proxmox VE для macOS на SwiftUI и WidgetKit. Мониторинг кластера, управление VM/LXC, телеметрия и диагностика собраны в одном интерфейсе. Секреты подключения хранятся в Apple Keychain.

### Новое в v0.2.3 · build 17

- **API Token без UUID-ограничения.** При добавлении и редактировании подходит любой непустой Secret; окружающие пробелы убираются. «Проверить соединение» и «Сохранить» доступны при заполненной форме. Пустое поле при редактировании сохраняет существующий секрет в Keychain, а неверные учётные данные показывают ответ 401 от Proxmox.
- **Домены и reverse proxy.** HTTPS без явного порта использует 443; указанный порт, префикс `/pve` и завершающий слэш обрабатываются корректно. Insecure SSL работает для IP и доменов. Ошибки DNS, SSL, таймаута/недоступности и авторизации имеют понятные сообщения.
- **Надёжнее автообновление.** Реальные проценты, скачанные/общие MB и скорость загрузки, отмена и проверка SHA-256. Отдельный фоновый скрипт ждёт завершения приложения, устанавливает проверенный бандл с откатом и запускает его снова. При ошибке подготовки можно открыть скачанный DMG вручную.
- **Отзывчивый интерфейс.** Сеть, декодирование JSON и запись виджетного кэша выполняются вне главного UI-потока. Зависшие циклы опроса отменяются, подробная телеметрия собирается ограниченными пакетами, устаревшие задачи не перезаписывают выбранный профиль. Упрощён поиск ближайшей точки на графиках; неактивная топология приостанавливает анимацию.
- **Резервный LAN-адрес.** Необязательный локальный HTTPS URL в профиле и быстрое переключение LAN/External в сайдбаре без повторного ввода секрета.

### Возможности v0.2.2 · build 16

- **Независимые AppIntent-виджеты машин.** Для каждого экземпляра: правый клик → **Изменить виджет → Машина**. Список заново читает кэш активного сервера, автоматически подхватывает новые CT/VM и показывает 🟢 Работает / ⚪️ Остановлен. При удалении выбранной машины появляется «Машина не найдена».
- **Обзор с картой на всю доступную высоту.** Кольца ноды сверху, интерактивная топология под ними, диагностика снизу. Хранилища перенесены в собственный раздел; каталог машин содержит только **Сетку / Стойку**, сортировку RAM/CPU/VMID/имя и фильтры состояния.
- **Навигация мышью.** Плавающие **+ / − / 100% / По размеру / В центр**, колесо мыши с зумом относительно курсора и жесты трекпада.
- **Фильтры на карте:** **Все / Работают / Выключены**, с плавным исчезновением карточек и их связей.
- **Стабильная расстановка.** Координаты узлов сохраняются относительно центра графа отдельно для профиля/ноды; прежняя расстановка мигрирует автоматически. Жёсткий барьер перетаскивания — 24 pt. При увеличении схему можно просматривать панорамированием; ограничение камеры предотвращает уход в пустоту. Кривые и бейджи следуют за узлами при зуме и ресайзе.
- **Быстрый поиск ⌘K.** Кликабельная строка в шапке, поиск по имени, VMID и IP, быстрый инспектор, SSH и Start/Reboot; Esc или клик снаружи закрывает меню. Перезагрузка сохраняет подтверждение.
- **Встроенная проверка обновлений.** Настройки → Обновления: changelog, проверка версии, SHA-256 и установка с перезапуском; проверка при запуске настраивается.

После обновления старый статический виджет машины может потребовать удаления и повторного добавления: он не содержит AppIntent-конфигурации. Для каждого нового виджета выберите свою машину. Фактическое расписание обновления виджетов определяет macOS.

### Возможности, добавленные в v0.2.1

- **Обновления в приложении:** Настройки → Обновления, проверка GitHub Releases при запуске по выбору пользователя, описание изменений и «Скачать и обновить». DMG проверяется по SHA-256; общий установщик заменяет приложение и запускает его снова.
- **VPN без SSH:** в профиле укажите имя внешнего туннеля, IP VPS и интерфейс. Доступность измеряется системным ping с Mac. Не нужны SSH-ключи, known_hosts или Python на Proxmox. Узел сохраняется на карте при недоступном ping; ICMP может блокироваться сетью. Скорость самого туннеля показывается прочерком, поскольку удалённые счётчики больше не запрашиваются. SSH остаётся только для вручную вызванной консоли; карта и виджеты от него не зависят.
- **Независимый кеш виджетов:** приложение атомарно пишет `~/Library/Application Support/ProxPulse/live_snapshot.json` при каждом опросе. Виджет сначала проверяет App Group, затем файл; более новый файл имеет приоритет над устаревшим групповым кешем. Для ad-hoc расширения предусмотрен точечный read-only sandbox entitlement к этому файлу ([документация Apple](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)). На этом Mac проверены разрешённый доступ без App Group и контрольный отказ без entitlement; другие Mac/версии macOS не проверялись.
- **Виджет Container / VM:** статус, vCPU, RAM, IP и uptime выбранной машины. Добавьте средний виджет машины в галерее и выберите машину через «Изменить виджет» для каждого экземпляра. Доступные машины относятся к активному профилю; адреса обновляются и при закрытой карте.
- **Установка одной командой и Homebrew:** установщик использует только штатные инструменты macOS; Homebrew — дополнительный способ, а не зависимость.

### Возможности рабочего пространства

- **Три режима отображения.** Обзор содержит постоянную карту топологии; вкладка «Машины» переключается между Сеткой и фронтальной Стойкой 19″. В стойке LXC занимает 1U, VM — 2U; статусные лампы, сетевые Tx/Rx-светодиоды и OLED-датчики CPU/RAM показывают состояние машин. Клик по машине в любом режиме открывает общий инспектор.
- **Живая топология сети.** Карта связывает ноду, мосты `vmbr*`, машины и VPN. Интерфейсы `awg*`, `wg*`, `tun*`, доступные API, дополняются явно настроенным внешним VPN из профиля. Узел VPS показывает адрес и RTT от этого Mac; световые частицы движутся по направлениям RX/TX с учётом трафика.
- **Интерактивный холст.** Перетаскивайте сервер, мост, VPS или любую машину. Расстановка сохраняется отдельно для профиля и ноды; **Auto-layout / Сбросить расстановку** возвращает авто-дерево, **В центр** подбирает масштаб и центр. Перетаскивание карточек ограничено видимой областью с отступом 24 pt. Увеличенную схему можно просматривать с помощью pan; кнопка «По размеру» снова показывает её целиком.
- **Умные бейджи скорости.** Микро-капсулы вида `↓ 286 B/s  ↑ 91 B/s` используют бирюзовый RX и фиолетовый TX. Если оба направления ниже 10 B/s, бейдж скрывается. Его центр всегда совпадает с точкой `t = 0.5` кривой Безье и следует за перемещением узлов.
- **Мастер создания VM и LXC.** Свободный VMID, шаблоны ОС, ISO, хранилища и мосты загружаются из Proxmox. Для LXC доступны unprivileged/nesting, пароль и SSH-ключи, rootfs, ядра, RAM/SWAP, DHCP/static, gateway, firewall и DNS. Для VM — ISO, QEMU Agent, шина/объём диска/discard, sockets/cores/CPU type, RAM/ballooning и модель сетевой карты. Поддерживаемые поля передаются в одноимённые параметры API; перед созданием можно проверить запрос. Машина создаётся выключенной.
- **Пользовательские пресеты.** Сохраните конфигурацию мастера и заполните форму в один клик. Пресеты хранятся локально; пароль не включается в пресет.
- **Безопасное удаление.** Удаление доступно для остановленной машины. Кнопка уничтожения разблокируется только после точного ввода VMID или имени; запрос использует `purge=1`. Перезагрузка и остановка также требуют подтверждения, а выполнение задачи отображается в карточке.
- **Глубокая телеметрия и новый инспектор.** CPU с лимитом vCPU, занятая/выделенная RAM, SWAP с янтарной подсветкой при использовании, диск, uptime, IP и скорости сети. Стеклянные KPI-плитки, компактная панель действий, SSH/веб-консоль и шесть неоновых графиков: CPU, RAM, SWAP, диск, RX, TX. Наведение показывает направляющую и значение ближайшего замера.
- **Настройки в сайдбаре.** Серверные профили и тест соединения, мгновенное RU/EN, Auto/Dark/Light, пять акцентных цветов (Electric Blue, Cyber Neon, Emerald Green, Royal Purple, Sunset Orange), опрос 2/4/10 секунд, порог диска 80/90/95% и категории уведомлений со звуком.
- **Виджеты Small / Medium / Large.** Кольца ноды, самые загруженные машины и обзор кластера на рабочем столе. Смена LIVE/DEMO или сервера сразу записывает новый снимок в App Group и запрашивает обновление таймлайна; фоновый опрос поддерживает актуальность кеша.

Сохранены кольца активности CPU/RAM/Disk/Net, дисковый sunburst-радар в духе DaisyDisk, меню-бар и детерминированная диагностика «Что случилось?»: OOM, диски, службы и сеть по доступным данным.

### Установка и обновление

Быстрый способ:

```sh
curl -fsSL https://raw.githubusercontent.com/makskondrasov9-dev/ProxPulse/main/scripts/install.sh | bash
```

Homebrew (этот репозиторий используется как tap):

```sh
brew tap makskondrasov9-dev/proxpulse https://github.com/makskondrasov9-dev/ProxPulse
brew install --cask makskondrasov9-dev/proxpulse/proxpulse
open /Applications/ProxPulse.app
```

Для ручной установки:

1. Скачайте **[ProxPulse-v0.2.3.dmg](https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.3/ProxPulse-v0.2.3.dmg)**. Рядом опубликована **[контрольная сумма SHA-256](https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.3/ProxPulse-v0.2.3.dmg.sha256)**.
2. Закройте старую версию. Откройте DMG и перетащите **ProxPulse.app → Applications**, подтвердив замену при обновлении.
3. Запустите `/Applications/ProxPulse.app`. Выберите DEMO или добавьте сервер в WORKSPACE / Настройках. Поддерживаются API Token и логин/пароль; самоподписанный SSL настраивается для каждого профиля.
4. Для виджетов: правый клик на рабочем столе → **Изменить виджеты** → **ProxPulse**. Сначала запустите приложение из Applications; держите его запущенным для свежих метрик.

Требования: **macOS 14 Sonoma+**, Intel или Apple Silicon, HTTPS-доступ к Proxmox VE. Для управления и создания машин нужны соответствующие права Proxmox.

Если macOS блокирует приложение после ручного копирования из доверенного DMG, снимите карантин только с его бандла:

```sh
xattr -cr /Applications/ProxPulse.app
```

Релиз подписан **ad-hoc**, без Developer ID и нотарификации Apple. При блокировке первого запуска используйте **Системные настройки → Конфиденциальность и безопасность → Всё равно открыть**, если доверяете загруженному релизу. [Инструкция Apple](https://support.apple.com/102445). При замене ad-hoc сборки macOS может повторно запросить доступ к сохранённым данным Keychain.

### Как устроены данные

- Профили и пресеты остаются локально. Пароли/API Secret находятся в **Keychain**, а не в UserDefaults, пресетах или кеше виджетов.
- VPN-проверка использует локальный ICMP ping. Отсутствие ответа может означать фильтрацию ICMP. RTT от Mac не подтверждает доступность сервиса внутри VPN; скорость туннеля без счётчиков неизвестна.
- Виджеты читают последний снимок `group.proxpulsedata` при каждом запросе таймлайна. Ручное переключение и первый LIVE-ответ немедленно запрашивают обновление; фоновые запросы ограничены 20 секундами. Фактическое время перерисовки определяет macOS.
- История графиков накапливается за текущую сессию, до 120 замеров. Неизвестные метрики обозначены прочерком. QEMU может не возвращать SWAP/занятое место внутри ОС; для IP VM нужен QEMU Guest Agent.
- Дисковый радар показывает логические хранилища Proxmox: общий backing pool может учитываться несколько раз. Размещение дисков гостей по хранилищам в LIVE автоматически не определяется.
- Уведомления локальные, работают при запущенном приложении. Диагностические рекомендации не выполняются автоматически.

## English

**ProxPulse** is a native Proxmox VE client for macOS, built with SwiftUI and WidgetKit. Monitor your cluster, manage VM/LXC workloads and inspect telemetry in one interface. Connection secrets stay in Apple Keychain.

### New in v0.2.3 · build 17

- **API tokens without UUID restrictions.** Add and edit profiles accept any nonempty secret, trimming surrounding whitespace. Test Connection and Save remain available for a complete form. Leaving the secret blank while editing preserves the existing Keychain credential; invalid credentials display Proxmox’s 401 response.
- **Domains and reverse proxies.** HTTPS without an explicit port uses 443; explicit ports, `/pve` path prefixes and trailing slashes are handled correctly. Insecure SSL supports both IP addresses and domains. DNS, SSL, timeout/connectivity and authentication errors have actionable messages.
- **More reliable updates.** Real percentages, downloaded/total MB and transfer speed, cancellation and SHA-256 verification. A separate background script waits for the app to exit, installs the verified bundle with rollback and relaunches it. A downloaded DMG can be opened manually if handoff preparation fails.
- **Responsive UI.** Networking, JSON decoding and widget cache writes stay off the main UI thread. Stalled poll cycles are cancelled, detailed telemetry is collected in bounded batches, and obsolete tasks cannot overwrite the selected profile. Chart hover sample lookup is cheaper; inactive topology animation pauses.
- **LAN fallback address.** An optional local HTTPS URL in each profile and a quick LAN/External sidebar switch, without reentering the secret.

### Features introduced in v0.2.2 · build 16

- **Independent AppIntent machine widgets.** Right-click each widget → **Edit Widget → Machine**. Each instance has its own selection. The picker rereads the active server cache, includes newly created CT/VM workloads, and shows 🟢 Running / ⚪️ Stopped. Deleted selections display “Machine not found”.
- **Full-height Overview topology.** Node activity rings above the map, diagnostics below. Storage has its own section; **Machines** contains only Grid/Rack, RAM/CPU/VMID/name sorting and status filters.
- **Mouse navigation.** Floating **+ / − / 100% / Fit to window / Recenter** controls, cursor-anchored mouse-wheel zoom and trackpad gestures.
- **Map filters:** **All / Running / Stopped**, with animated removal of matching nodes and links.
- **Stable layout.** Profile/node-scoped coordinates are stored relative to the graph center; existing layouts migrate automatically. Node dragging has a hard 24 pt boundary. Zoomed content can be explored with pan; camera bounds prevent moving the graph into empty space. Curves and badges track nodes during zoom and resize.
- **Quick Search ⌘K.** Click the header capsule or press ⌘K, search by name, VMID or IP, then open the inspector/SSH or Start/Reboot. Esc or an outside click dismisses it. Reboots retain confirmation.
- **Built-in update checks.** Settings → Updates includes release notes, version comparison, SHA-256 verification and installation/relaunch, with optional startup checks.

An existing static machine widget may need to be removed and added again after updating because it has no AppIntent configuration. Choose a machine separately for each new widget. macOS controls actual widget refresh scheduling.

### Features introduced in v0.2.1

- **In-app updates:** Settings → Updates, optional launch checks, GitHub release notes and Download and update. SHA-256 is verified before the shared installer replaces and relaunches the app.
- **VPN without SSH:** configure a tunnel name, VPS IP and interface in the server profile. A local system ping measures reachability. No SSH keys, known_hosts or Python on Proxmox are required. The node stays on the map if ping is unavailable; ICMP may be filtered. Tunnel rates show a dash because remote counters are no longer queried. SSH remains available for manually opened consoles; the map and widgets do not depend on it.
- **Independent widget cache:** every poll atomically writes `~/Library/Application Support/ProxPulse/live_snapshot.json`. Widgets check the App Group first, then this file; a newer file wins over stale group data. A narrow [read-only sandbox exception](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html) grants the ad-hoc extension access to that exact file. A signed sandbox probe without App Group could read it on this Mac, while the negative control without the file entitlement could not. Other Macs/macOS versions have not been tested.
- **Container / VM widget:** status, vCPU, RAM, IP and uptime for one selected machine. Add the medium machine widget in the gallery and choose its machine through Edit Widget. Available machines belong to the active profile; addresses refresh even when the map is closed.
- **One-command installation and Homebrew:** the installer needs only built-in macOS tools; Homebrew is an optional installation route.

### Workspace features

- **Three workspace modes.** Overview contains the permanent Topology Map; Machines switches between Grid and the front-facing 19″ Rack. Rack blades use 1U for LXC and 2U for VM, with status lamps, Tx/Rx LEDs and OLED-style CPU/RAM meters. Clicking a machine in any mode opens the shared inspector.
- **Live network topology.** Connect the node, `vmbr*` bridges, machines and VPN. API-visible `awg*`, `wg*` and `tun*` interfaces are supplemented by an explicitly configured external VPN in the profile. The VPS node shows its address and RTT from this Mac. Directional light particles follow RX/TX traffic.
- **Interactive canvas.** Drag the server, bridges, VPS or machines. Positions persist per profile and node; **Auto-layout** restores the tree, while **Recenter** fits and centers it. Node dragging has a hard 24 pt boundary. Zoomed content can be explored with pan; Fit to window shows the complete graph again.
- **Smart speed badges.** Intrinsic-sized capsules such as `↓ 286 B/s  ↑ 91 B/s` use cyan RX and purple TX. A badge disappears when both directions are below 10 B/s. Its center follows the exact `t = 0.5` point of its cubic Bezier curve as nodes move.
- **VM and LXC creation wizard.** Load a free VMID, OS templates, ISO images, storage and bridges from Proxmox. LXC supports unprivileged/nesting, password/SSH keys, rootfs, cores, RAM/SWAP, DHCP/static addressing, gateway, firewall and DNS. VM supports ISO, QEMU Agent, disk bus/size/discard, sockets/cores/CPU type, RAM/ballooning and NIC model. Supported fields map directly to Proxmox API parameters; review the request before creation. New machines remain stopped.
- **User presets.** Save a wizard configuration locally and apply it in one click. Passwords are excluded from presets.
- **Guarded deletion.** A machine must be stopped. Destruction requires typing its exact VMID or name before a `purge=1` request. Reboot and stop actions also require confirmation; cards track pending operations.
- **Advanced telemetry and redesigned inspector.** CPU/vCPU allocation, used/allocated RAM, amber SWAP activity, disk, uptime, IP addresses and network rates. Glass KPI tiles, a compact action toolbar, SSH/web console and six neon history charts: CPU, RAM, SWAP, disk, RX and TX. Hover reveals a guide and the nearest sample value.
- **Sidebar settings.** Profiles and connection tests, instant Russian/English, Auto/Dark/Light, five accents (Electric Blue, Cyber Neon, Emerald Green, Royal Purple, Sunset Orange), 2/4/10-second polling, 80/90/95% disk thresholds and notification categories with sound.
- **Small, Medium and Large desktop widgets.** Node rings, top resource consumers and cluster overview. Switching LIVE/DEMO or server immediately writes a fresh App Group snapshot and requests a timeline reload; polling keeps the cache current.

Also included: CPU/RAM/Disk/Net activity rings, a DaisyDisk-style storage sunburst, menu-bar overview and deterministic incident diagnostics based on available OOM, disk, service and network evidence.

### Install or upgrade

One command:

```sh
curl -fsSL https://raw.githubusercontent.com/makskondrasov9-dev/ProxPulse/main/scripts/install.sh | bash
```

Homebrew (this repository also serves as a tap):

```sh
brew tap makskondrasov9-dev/proxpulse https://github.com/makskondrasov9-dev/ProxPulse
brew install --cask makskondrasov9-dev/proxpulse/proxpulse
open /Applications/ProxPulse.app
```

Manual DMG installation:

1. Download **[ProxPulse-v0.2.3.dmg](https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.3/ProxPulse-v0.2.3.dmg)** and its **[SHA-256 checksum](https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.3/ProxPulse-v0.2.3.dmg.sha256)**.
2. Quit the previous version. Open the DMG and drag **ProxPulse.app → Applications**, replacing the app when upgrading.
3. Launch `/Applications/ProxPulse.app`. Try DEMO or add a server in WORKSPACE / Settings. API tokens and password authentication are supported; self-signed TLS can be enabled per profile.
4. Right-click the desktop → **Edit Widgets** → **ProxPulse**. Launch the app from Applications first and keep it running for fresh metrics.

Requires **macOS 14 Sonoma+**, Intel or Apple Silicon, HTTPS access to Proxmox VE and appropriate Proxmox permissions for management/provisioning actions.

For a trusted manually installed download, remove quarantine from this app only:

```sh
xattr -cr /Applications/ProxPulse.app
```

This release is **ad-hoc signed**, without Developer ID or Apple notarization. If macOS blocks the first launch and you trust the download, use **System Settings → Privacy & Security → Open Anyway**. See [Apple's instructions](https://support.apple.com/en-us/102445). Replacing an ad-hoc build may prompt for Keychain access again.

### Data and operational details

- Profiles and presets stay local. Passwords and API secrets stay in **Keychain**, outside UserDefaults, presets and widget snapshots.
- VPN probing uses local ICMP ping. A missing reply may mean ICMP filtering. Mac-to-endpoint RTT does not prove service availability inside the VPN, and tunnel rates are unknown without counters.
- Widgets read the latest `group.proxpulsedata` snapshot on every timeline request. Manual source changes and the first LIVE response request an immediate reload; background requests are limited to once every 20 seconds. macOS controls actual widget refresh timing.
- Charts retain up to 120 samples during the current session. Missing metrics display a dash. QEMU guest SWAP/filesystem usage can be unavailable; VM IP addresses require QEMU Guest Agent.
- The radar reports logical storage, which may share physical backing capacity. Live guest-to-storage placement is not inferred automatically.
- Notifications are local and require the app to run. Diagnostic recommendations are not executed automatically.

## Build from source / Сборка

Requires Swift 6 and the macOS SDK: Xcode 16+ or compatible Command Line Tools. There are no third-party runtime dependencies.

```sh
git clone https://github.com/makskondrasov9-dev/ProxPulse.git
cd ProxPulse
./scripts/verify-local.sh       # Build, API/core/UI checks, WidgetKit executable
./scripts/verify-profile-form.sh # Native token-form regression (test-only Python 3 + OpenSSL)
./scripts/build-release.sh      # Optimized universal app + WidgetKit extension
./scripts/create-dmg.sh         # dist/ProxPulse-v0.2.3.dmg + SHA-256
```

The compatibility helper confines any SDK compatibility adjustments to `.build`; it does not modify the SDK. On restricted development hosts, `PROXPULSE_LOCAL_CACHE=1` keeps SwiftPM caches inside the workspace. `PROXPULSE_REUSE_ICON=1` reuses the checked-in icon during release builds.

Open **ProxPulse.xcodeproj** and select the **ProxPulse** scheme for Xcode development. `project.yml` is the XcodeGen source; regenerate with `xcodegen generate` after project changes. Command Line Tools builds compile runtime targets with SwiftPM and link the WidgetKit entry point separately. XCTest targets require full Xcode; standalone API fixtures and native UI checks are included for CLT-only development.

For Developer ID distribution, configure your Team and registered App Group, then sign and notarize the app.

```text
Sources/ProxPulseCore       API actor, models, Keychain, diagnostics, shared widget state
Sources/ProxPulse           SwiftUI app, dashboard, inspector, settings, notifications
Sources/ProxPulseWidgetUI   Widget views and timeline provider
WidgetExtension            WidgetKit entry point
Resources                  CoreGraphics icon and iconset
scripts                    Build, verification, packaging and installation
```

UI screenshots can be regenerated from the DEBUG app with `--release-media`. The command renders only DEMO fixtures into `docs/images/`; it does not require server credentials. See [CHANGELOG.md](CHANGELOG.md) for release notes.
