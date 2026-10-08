#include "TaskbarProgress.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <QWindow>

#ifdef Q_OS_WIN
#include <windows.h>
#include <objectarray.h>
#include <propsys.h>
#include <shobjidl.h>

namespace {
// PKEY_Title, spelled out so no extra import library is needed.
const PROPERTYKEY titleKey{{0xF29F85E0, 0x4FF9, 0x1068, {0xAB, 0x91, 0x08, 0x00, 0x2B, 0x27, 0xB3, 0xD9}}, 2};

// A link that starts Kadron with arguments, titled for the jump list.
IShellLinkW *kadronLink(const QString &arguments, const QString &title, const QString &description)
{
    IShellLinkW *link = nullptr;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, reinterpret_cast<void **>(&link))))
        return nullptr;
    const auto exe = QDir::toNativeSeparators(QCoreApplication::applicationFilePath());
    link->SetPath(reinterpret_cast<LPCWSTR>(exe.utf16()));
    link->SetArguments(reinterpret_cast<LPCWSTR>(arguments.utf16()));
    link->SetIconLocation(reinterpret_cast<LPCWSTR>(exe.utf16()), 0);
    link->SetDescription(reinterpret_cast<LPCWSTR>(description.utf16()));
    IPropertyStore *properties = nullptr;
    if (SUCCEEDED(link->QueryInterface(IID_IPropertyStore, reinterpret_cast<void **>(&properties)))) {
        PROPVARIANT value;
        PropVariantInit(&value);
        const auto bytes = (title.size() + 1) * sizeof(wchar_t);
        value.vt = VT_LPWSTR;
        value.pwszVal = static_cast<LPWSTR>(CoTaskMemAlloc(bytes));
        if (value.pwszVal) {
            memcpy(value.pwszVal, title.utf16(), bytes);
            properties->SetValue(titleKey, value);
            properties->Commit();
        }
        PropVariantClear(&value);
        properties->Release();
    }
    return link;
}

QString linkArguments(IUnknown *item)
{
    IShellLinkW *link = nullptr;
    if (FAILED(item->QueryInterface(IID_IShellLinkW, reinterpret_cast<void **>(&link))))
        return {};
    wchar_t buffer[INFOTIPSIZE] = {};
    link->GetArguments(buffer, INFOTIPSIZE);
    link->Release();
    return QString::fromWCharArray(buffer);
}
}
#endif

TaskbarProgress::TaskbarProgress(QObject *parent) : QObject(parent) {}

TaskbarProgress::~TaskbarProgress()
{
#ifdef Q_OS_WIN
    if (m_taskbar)
        static_cast<ITaskbarList3 *>(m_taskbar)->Release();
#endif
}

void TaskbarProgress::setProgress(QObject *window, int percent, bool error)
{
#ifdef Q_OS_WIN
    const auto qwindow = qobject_cast<QWindow *>(window);
    if (!qwindow)
        return;
    if (!m_taskbar && !m_triedCreate) {
        m_triedCreate = true;
        ITaskbarList3 *taskbar = nullptr;
        if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_ITaskbarList3,
                                       reinterpret_cast<void **>(&taskbar)))
            && SUCCEEDED(taskbar->HrInit()))
            m_taskbar = taskbar;
        else if (taskbar)
            taskbar->Release();
    }
    if (!m_taskbar)
        return;
    const auto taskbar = static_cast<ITaskbarList3 *>(m_taskbar);
    const auto hwnd = reinterpret_cast<HWND>(qwindow->winId());
    if (percent == -2) {
        taskbar->SetProgressState(hwnd, TBPF_INDETERMINATE);
        return;
    }
    if (percent < 0) {
        taskbar->SetProgressState(hwnd, TBPF_NOPROGRESS);
        return;
    }
    taskbar->SetProgressState(hwnd, error ? TBPF_ERROR : TBPF_NORMAL);
    taskbar->SetProgressValue(hwnd, qBound(0, percent, 100), 100);
#else
    Q_UNUSED(window) Q_UNUSED(percent) Q_UNUSED(error)
#endif
}

void TaskbarProgress::flash(QObject *window)
{
#ifdef Q_OS_WIN
    const auto qwindow = qobject_cast<QWindow *>(window);
    if (!qwindow || !qwindow->isVisible() || qwindow->isActive())
        return;
    FLASHWINFO info{sizeof(FLASHWINFO), reinterpret_cast<HWND>(qwindow->winId()), FLASHW_TRAY | FLASHW_TIMERNOFG, 0, 0};
    FlashWindowEx(&info);
#else
    Q_UNUSED(window)
#endif
}

void TaskbarProgress::setJumpList(const QVariantList &recent)
{
#ifdef Q_OS_WIN
    // Screenshot runs leave the real jump list alone.
    if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT"))
        return;
    ICustomDestinationList *list = nullptr;
    if (FAILED(CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER, IID_ICustomDestinationList,
                                reinterpret_cast<void **>(&list))))
        return;
    UINT maxItems = 0;
    IObjectArray *removed = nullptr;
    if (FAILED(list->BeginList(&maxItems, IID_IObjectArray, reinterpret_cast<void **>(&removed)))) {
        list->Release();
        return;
    }
    // Windows refuses a list that brings back an item the user removed.
    QStringList refused;
    UINT removedCount = 0;
    removed->GetCount(&removedCount);
    for (UINT i = 0; i < removedCount; ++i) {
        IUnknown *item = nullptr;
        if (SUCCEEDED(removed->GetAt(i, IID_IUnknown, reinterpret_cast<void **>(&item)))) {
            refused << linkArguments(item);
            item->Release();
        }
    }
    removed->Release();

    const auto collection = [] {
        IObjectCollection *items = nullptr;
        CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr, CLSCTX_INPROC_SERVER, IID_IObjectCollection,
                         reinterpret_cast<void **>(&items));
        return items;
    };
    const auto append = [list](IObjectCollection *items, const wchar_t *category) {
        UINT count = 0;
        items->GetCount(&count);
        IObjectArray *array = nullptr;
        if (count && SUCCEEDED(items->QueryInterface(IID_IObjectArray, reinterpret_cast<void **>(&array)))) {
            if (category)
                list->AppendCategory(category, array);
            else
                list->AddUserTasks(array);
            array->Release();
        }
        items->Release();
    };

    if (auto *files = collection()) {
        for (const auto &entry : recent) {
            const auto map = entry.toMap();
            const auto path = QUrl(map.value("url").toString()).toLocalFile();
            if (path.isEmpty() || !QFileInfo::exists(path))
                continue;
            // Like Recent on the start page: a project opens, media replaces the editor's.
            const auto arguments = QStringLiteral("--tool=%1 \"%2\"")
                                       .arg(map.value("project").toBool() ? QStringLiteral("project") : QStringLiteral("open"),
                                            QDir::toNativeSeparators(path));
            if (refused.contains(arguments))
                continue;
            if (auto *link = kadronLink(arguments, QFileInfo(path).fileName(), QDir::toNativeSeparators(path))) {
                files->AddObject(link);
                link->Release();
            }
        }
        append(files, L"Recent");
    }
    if (auto *tasks = collection()) {
        const QList<std::pair<QString, QString>> tools{
            {QStringLiteral("edit"), QStringLiteral("Video editor")},
            {QStringLiteral("download"), QStringLiteral("Download")},
            {QStringLiteral("compress"), QStringLiteral("Compress")},
            {QStringLiteral("gif"), QStringLiteral("GIF Studio")},
            {QStringLiteral("images"), QStringLiteral("Images")},
            {QStringLiteral("pdf"), QStringLiteral("PDF tools")},
        };
        for (const auto &[tool, title] : tools)
            if (auto *link = kadronLink(QStringLiteral("--tool=") + tool, title, title)) {
                tasks->AddObject(link);
                link->Release();
            }
        append(tasks, nullptr);
    }
    list->CommitList();
    list->Release();
#else
    Q_UNUSED(recent)
#endif
}
