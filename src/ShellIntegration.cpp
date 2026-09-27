#include "ShellIntegration.h"

#include <QCoreApplication>
#include <QDir>
#include <QSettings>

#ifdef Q_OS_WIN
#include <windows.h>
#include <shlobj.h>
#endif

QList<ShellIntegration::Group> ShellIntegration::groups()
{
    return {
        { { "mp4", "mov", "mkv", "webm", "avi", "m4v", "wmv", "mpg", "mpeg", "ts" },
          { { "1edit", "Edit in Kadron", "edit" },
            { "2reframe", "Reframe for vertical", "reframe" },
            { "3compress", "Compress", "compress" },
            { "4gif", "Make a GIF", "gif" },
            { "5audio", "Extract audio", "audio" } } },
        { { "mp3", "wav", "flac", "m4a", "aac", "ogg", "opus" },
          { { "1audio", "Convert audio", "audio" } } },
        { { "jpg", "jpeg", "png", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff" },
          { { "1images", "Resize and convert", "images" },
            { "2pdf", "Combine into a PDF", "images-to-pdf" } } },
        { { "pdf" },
          { { "1pdf", "Open in PDF Tools", "pdf" } } },
    };
}

QStringList ShellIntegration::tools()
{
    QStringList result;
    for (const auto &group : groups())
        for (const auto &action : group.actions)
            if (!result.contains(action.tool))
                result << action.tool;
    return result;
}

ShellIntegration::ShellIntegration(QObject *parent)
    : QObject(parent)
{
}

bool ShellIntegration::supported() const
{
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}

bool ShellIntegration::enabled() const
{
    return installed();
}

void ShellIntegration::setEnabled(bool enabled)
{
    if (enabled == installed())
        return;
    if (enabled)
        install(QCoreApplication::applicationFilePath());
    else
        uninstall();
    // The installer reads this on updates, so a menu turned off stays off.
    QSettings().setValue(QStringLiteral("preferences/explorerMenu"), enabled);
    emit enabledChanged();
}

#ifdef Q_OS_WIN
static std::wstring wide(const QString &text)
{
    return text.toStdWString();
}

static QString keyFor(const QString &extension)
{
    return QStringLiteral("Software\\Classes\\SystemFileAssociations\\.%1\\shell\\Kadron").arg(extension);
}

static bool setValue(const QString &key, const QString &name, const QString &value)
{
    const auto k = wide(key), n = wide(name), v = wide(value);
    return RegSetKeyValueW(HKEY_CURRENT_USER, k.c_str(), name.isEmpty() ? nullptr : n.c_str(), REG_SZ,
                           v.c_str(), DWORD((v.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
}
#endif

bool ShellIntegration::install(const QString &executable)
{
#ifdef Q_OS_WIN
    const auto exe = QDir::toNativeSeparators(executable);
    bool ok = true;
    for (const auto &group : groups()) {
        for (const auto &extension : group.extensions) {
            const auto root = keyFor(extension);
            // A fresh tree each time, so renamed or dropped actions don't linger.
            RegDeleteTreeW(HKEY_CURRENT_USER, wide(root).c_str());
            ok &= setValue(root, "MUIVerb", "Kadron");
            ok &= setValue(root, "Icon", QStringLiteral("\"%1\",0").arg(exe));
            ok &= setValue(root, "SubCommands", QString());
            ok &= setValue(root, "MultiSelectModel", "Player");
            for (const auto &action : group.actions) {
                const auto verb = root + "\\shell\\" + action.key;
                ok &= setValue(verb, "MUIVerb", action.label);
                ok &= setValue(verb, "MultiSelectModel", "Player");
                ok &= setValue(verb + "\\command", QString(),
                               QStringLiteral("\"%1\" --tool=%2 \"%3\"").arg(exe, action.tool, "%1"));
            }
        }
    }
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
    return ok;
#else
    Q_UNUSED(executable)
    return false;
#endif
}

void ShellIntegration::uninstall()
{
#ifdef Q_OS_WIN
    for (const auto &group : groups())
        for (const auto &extension : group.extensions)
            RegDeleteTreeW(HKEY_CURRENT_USER, wide(keyFor(extension)).c_str());
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
#endif
}

bool ShellIntegration::installed()
{
#ifdef Q_OS_WIN
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, wide(keyFor("mp4")).c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS)
        return false;
    RegCloseKey(key);
    return true;
#else
    return false;
#endif
}
