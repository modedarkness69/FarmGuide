# FarmGuide

## Назначение
Аддон WoW Retail (Midnight 12.x) на Lua: маршруты сбора руды и трав, полноэкранный HUD, аналитика аукциона, подсказки. Подпись «made by modedarkness», репо `modedarkness69/FarmGuide`, MIT.

## Структура
- `FarmGuide.toc` — версия интерфейса, порядок файлов, SavedVariables `FarmGuideDB`
- `Core.lua` (события, БД, координаты, цены), `Gather.lua` (сбор, точки), `Route.lua` (маршрут)
- `Prices.lua` (сканы аукциона), `HUD.lua`, `UI.lua` (окно, команды `/fg`), `Options.lua` (настройки, кнопка у мини-карты)

## Запуск
- Папка связана junction с `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\FarmGuide`
- В игре: `/reload`; ошибки Lua: `/console scriptErrors 1`
- Автотестов нет

## Порты и внешние сервисы
- Нет: аддоны WoW без доступа к сети

## Не трогать
- Автоматизация сбора и движения запрещена правилами игры — только подсказки
- Подпись «made by modedarkness» в интерфейсе

## Не читать без запроса
- `WTF\` и SavedVariables игры

## Отладка
- Только ошибки Lua в игре (скриншот или текст от владельца)

## Статус (2026-11-10)
- Версия 1.1.0; в игре ещё не проверялся — ждём ошибки Lua и скриншоты от владельца
