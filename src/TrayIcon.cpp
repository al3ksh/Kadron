#include "TrayIcon.h"

#ifdef Q_OS_WIN
#include <windows.h>
#include <shellapi.h>

namespace {
constexpr UINT TrayCallback = WM_APP + 1;
constexpr UINT TrayId = 1;
enum MenuCommand : UINT { MenuOpen = 1, MenuQuit = 2 };

LRESULT CALLBACK trayWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    if (auto *tray = reinterpret_cast<TrayIcon *>(GetWindowLongPtrW(window, GWLP_USERDATA)))
        return static_cast<LRESULT>(tray->handleMessage(message, wParam, lParam));
    return DefWindowProcW(window, message, wParam, lParam);
}

// Win32 popup menus only go dark through uxtheme's unnamed exports
// (SetPreferredAppMode #135, FlushMenuThemes #136, Windows 10 1903+).
void applyMenuTheme(bool dark)
{
    static const auto uxtheme = LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!uxtheme)
        return;
    using SetPreferredAppMode = int(WINAPI *)(int);
    using FlushMenuThemes = void(WINAPI *)();
    static const auto setMode = reinterpret_cast<SetPreferredAppMode>(GetProcAddress(uxtheme, MAKEINTRESOURCEA(135)));
    static const auto flush = reinterpret_cast<FlushMenuThemes>(GetProcAddress(uxtheme, MAKEINTRESOURCEA(136)));
    if (!setMode || !flush)
        return;
    setMode(dark ? 2 : 3); // ForceDark : ForceLight
    flush();
}

void copyText(wchar_t *target, size_t capacity, const QString &text)
{
    const auto length = qMin<qsizetype>(text.size(), qsizetype(capacity) - 1);
    text.left(length).toWCharArray(target);
    target[length] = L'\0';
}
}

TrayIcon::TrayIcon(QObject *parent)
    : QObject(parent)
{
    const auto instance = GetModuleHandleW(nullptr);
    WNDCLASSW windowClass {};
    windowClass.lpfnWndProc = trayWindowProc;
    windowClass.hInstance = instance;
    windowClass.lpszClassName = L"KadronTrayWindow";
    RegisterClassW(&windowClass);
    // A plain hidden top-level window: message-only windows miss the
    // TaskbarCreated broadcast sent when Explorer restarts.
    auto window = CreateWindowExW(0, windowClass.lpszClassName, L"Kadron", 0, 0, 0, 0, 0, nullptr, nullptr, instance, nullptr);
    if (window)
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    m_window = window;
    m_taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
    m_icon = LoadImageW(instance, L"IDI_ICON1", IMAGE_ICON, GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0);
    // Notifications refuse NIIF_LARGE_ICON with a small icon.
    m_largeIcon = LoadImageW(instance, L"IDI_ICON1", IMAGE_ICON, GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON), 0);
}

TrayIcon::~TrayIcon()
{
    remove();
    if (m_window)
        DestroyWindow(static_cast<HWND>(m_window));
    if (m_icon)
        DestroyIcon(static_cast<HICON>(m_icon));
    if (m_largeIcon)
        DestroyIcon(static_cast<HICON>(m_largeIcon));
}

bool TrayIcon::supported() const
{
    return m_window != nullptr;
}

void TrayIcon::setVisible(bool visible)
{
    if (m_visible == visible)
        return;
    m_visible = visible;
    m_transient = false;
    if (visible)
        add();
    else
        remove();
    emit visibleChanged();
}

bool TrayIcon::add()
{
    if (!m_window || m_added)
        return m_added;
    NOTIFYICONDATAW data {};
    data.cbSize = sizeof(data);
    data.hWnd = static_cast<HWND>(m_window);
    data.uID = TrayId;
    data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    data.uCallbackMessage = TrayCallback;
    data.hIcon = static_cast<HICON>(m_icon);
    copyText(data.szTip, std::size(data.szTip), QStringLiteral("Kadron"));
    m_added = Shell_NotifyIconW(NIM_ADD, &data);
    return m_added;
}

void TrayIcon::remove()
{
    if (!m_added)
        return;
    NOTIFYICONDATAW data {};
    data.cbSize = sizeof(data);
    data.hWnd = static_cast<HWND>(m_window);
    data.uID = TrayId;
    Shell_NotifyIconW(NIM_DELETE, &data);
    m_added = false;
}

void TrayIcon::showMessage(const QString &title, const QString &text)
{
    if (!m_added) {
        if (!add())
            return;
        m_transient = true;
    }
    NOTIFYICONDATAW data {};
    data.cbSize = sizeof(data);
    data.hWnd = static_cast<HWND>(m_window);
    data.uID = TrayId;
    data.uFlags = NIF_INFO;
    data.dwInfoFlags = NIIF_USER | NIIF_LARGE_ICON;
    data.hBalloonIcon = static_cast<HICON>(m_largeIcon ? m_largeIcon : m_icon);
    copyText(data.szInfoTitle, std::size(data.szInfoTitle), title);
    copyText(data.szInfo, std::size(data.szInfo), text);
    Shell_NotifyIconW(NIM_MODIFY, &data);
}

void TrayIcon::showMenu()
{
    auto window = static_cast<HWND>(m_window);
    applyMenuTheme(m_dark);
    auto menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, MenuOpen, L"Open Kadron");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, MenuQuit, L"Quit Kadron");
    SetMenuDefaultItem(menu, MenuOpen, FALSE);
    POINT cursor;
    GetCursorPos(&cursor);
    // Without the foreground switch the menu would not close on an outside click.
    SetForegroundWindow(window);
    const auto command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y, 0, window, nullptr);
    PostMessageW(window, WM_NULL, 0, 0);
    DestroyMenu(menu);
    if (command == MenuOpen)
        emit activated();
    else if (command == MenuQuit)
        emit quitRequested();
}

long long TrayIcon::handleMessage(unsigned message, unsigned long long wParam, long long lParam)
{
    const auto window = static_cast<HWND>(m_window);
    if (message == TrayCallback) {
        switch (LOWORD(lParam)) {
        case WM_LBUTTONUP:
            emit activated();
            break;
        case NIN_BALLOONUSERCLICK:
        case NIN_BALLOONTIMEOUT:
        case NIN_BALLOONHIDE:
            // An icon added only for the message leaves with it.
            if (m_transient && !m_visible) {
                m_transient = false;
                remove();
            }
            if (LOWORD(lParam) == NIN_BALLOONUSERCLICK)
                emit messageClicked();
            break;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
            showMenu();
            break;
        }
        return 0;
    }
    if (message == m_taskbarCreated && m_taskbarCreated) {
        m_added = false;
        if (m_visible)
            add();
        return 0;
    }
    return DefWindowProcW(window, message, WPARAM(wParam), LPARAM(lParam));
}

#else

TrayIcon::TrayIcon(QObject *parent) : QObject(parent) {}
TrayIcon::~TrayIcon() = default;
bool TrayIcon::supported() const { return false; }
void TrayIcon::setVisible(bool visible)
{
    if (m_visible == visible)
        return;
    m_visible = visible;
    emit visibleChanged();
}
void TrayIcon::showMessage(const QString &, const QString &) {}
long long TrayIcon::handleMessage(unsigned, unsigned long long, long long) { return 0; }
bool TrayIcon::add() { return false; }
void TrayIcon::remove() {}
void TrayIcon::showMenu() {}

#endif
