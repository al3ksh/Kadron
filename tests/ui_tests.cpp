#include <QMetaMethod>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>
#include <QQmlExtensionPlugin>

Q_IMPORT_QML_PLUGIN(KadronPlugin)

class UiTests final : public QObject
{
    Q_OBJECT
    QTemporaryDir m_settingsDir;

private slots:
    void initTestCase();
    void init();
    void timelineInteractions();
    void toolControls();
    void studioNavigation();
    void toolInputs();
    void updateCard();
    void appearance();
    void intro();
};

// Components come from the same Kadron module the app ships; any QML warning
// (unresolved Theme token, binding loop, bad anchor) fails the test.
static std::unique_ptr<QObject> createFromModule(QQmlEngine &engine, const char *type)
{
    QQmlComponent component(&engine);
    component.loadFromModule("Kadron", type);
    if (!component.isReady())
        qWarning("%s", qPrintable(component.errorString()));
    return std::unique_ptr<QObject>(component.create());
}

static QMetaMethod signalOf(QObject *object, const char *name)
{
    const auto index = object->metaObject()->indexOfSignal(name);
    return index < 0 ? QMetaMethod() : object->metaObject()->method(index);
}

static QVariantMap clip(const QString &name, double durationMs, double inMs, double outMs)
{
    return {{"url", QUrl::fromLocalFile("/nonexistent/" + name)}, {"name", name}, {"durationMs", durationMs},
            {"inMs", inMs}, {"outMs", outMs}, {"lengthMs", outMs - inMs}};
}

void UiTests::initTestCase()
{
    // The app runs the Basic style; native styles reject custom control parts.
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    // Prefs persists through Settings; keep test runs out of the real profile.
    QCoreApplication::setOrganizationName(QStringLiteral("KadronTests"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("kadron.test"));
    QCoreApplication::setApplicationName(QStringLiteral("KadronUiTests"));
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDir.path());
}

void UiTests::init()
{
    QTest::failOnWarning(QRegularExpression("qrc:|file:|QML"));
}

void UiTests::timelineInteractions()
{
    QQmlEngine engine;
    auto object = createFromModule(engine, "Timeline");
    auto *timeline = qobject_cast<QQuickItem *>(object.get());
    QVERIFY(timeline);
    // Two 4 s clips across 800 px: 0.1 px per ms, clip B starts at x = 400.
    timeline->setWidth(800);
    timeline->setHeight(150);
    timeline->setProperty("clips", QVariantList{clip("a.mp4", 4000, 0, 4000), clip("b.mp4", 4000, 0, 4000)});
    timeline->setProperty("activeIndex", 0);
    timeline->setProperty("playheadMs", 0);

    QQuickWindow window;
    window.setGeometry(50, 50, 800, 150);
    timeline->setParentItem(window.contentItem());
    window.show();
    QVERIFY(QTest::qWaitForWindowExposed(&window));
    QCOMPARE(timeline->property("totalMs").toDouble(), 8000.0);

    QSignalSpy scrub(timeline, signalOf(timeline, "scrubRequested(double)"));
    QSignalSpy scrubDone(timeline, signalOf(timeline, "scrubFinished()"));
    QSignalSpy select(timeline, signalOf(timeline, "selectRequested(int)"));
    QSignalSpy trim(timeline, signalOf(timeline, "trimRequested(int,double,double,double)"));
    QSignalSpy move(timeline, signalOf(timeline, "moveRequested(int,int)"));
    QSignalSpy trimPreview(timeline, signalOf(timeline, "trimPreviewRequested(int,double)"));
    QVERIFY(trimPreview.isValid());
    QVERIFY(scrub.isValid() && scrubDone.isValid() && select.isValid() && trim.isValid() && move.isValid());

    // Ruler click scrubs in sequence time.
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(300, 15));
    QVERIFY(scrub.count() > 0);
    QVERIFY(qAbs(scrub.last().first().toDouble() - 3000.0) < 20);
    QVERIFY(scrubDone.count() > 0);

    // Ruler drag keeps scrubbing.
    scrub.clear();
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(300, 15));
    QTest::mouseMove(&window, QPoint(650, 15));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(650, 15));
    QVERIFY(qAbs(scrub.last().first().toDouble() - 6500.0) < 20);

    // Clicking another clip selects it and seeks inside it.
    scrub.clear();
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(500, 100));
    QCOMPARE(select.count(), 1);
    QCOMPARE(select.last().first().toInt(), 1);
    QVERIFY(qAbs(scrub.last().first().toDouble() - 5000.0) < 20);

    // Dragging the trailing edge of clip A trims its out point.
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(395, 100));
    QTest::mouseMove(&window, QPoint(370, 100));
    QTest::mouseMove(&window, QPoint(345, 100));
    QVERIFY(trimPreview.count() > 0);
    QCOMPARE(trim.count(), 0);
    QCOMPARE(timeline->property("trimIndex").toInt(), 0);
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(345, 100));
    QCOMPARE(trim.count(), 1);
    QCOMPARE(timeline->property("trimIndex").toInt(), -1);
    QCOMPARE(trim.last().at(0).toInt(), 0);
    QCOMPARE(trim.last().at(1).toDouble(), 0.0);
    QVERIFY(qAbs(trim.last().at(2).toDouble() - 3500.0) < 20);

    // Escape abandons a trim in progress.
    trim.clear();
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(395, 100));
    QTest::mouseMove(&window, QPoint(370, 100));
    QTest::mouseMove(&window, QPoint(345, 100));
    QTest::keyClick(&window, Qt::Key_Escape);
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(345, 100));
    QCOMPARE(trim.count(), 0);

    // Dragging the leading edge of clip B trims its in point.
    trim.clear();
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(405, 100));
    QTest::mouseMove(&window, QPoint(425, 100));
    QTest::mouseMove(&window, QPoint(455, 100));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(455, 100));
    QCOMPARE(trim.last().at(0).toInt(), 1);
    QVERIFY(qAbs(trim.last().at(1).toDouble() - 500.0) < 20);
    QCOMPARE(trim.last().at(2).toDouble(), 4000.0);

    // Dragging a clip body past its neighbour reorders.
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(200, 100));
    QTest::mouseMove(&window, QPoint(230, 100));
    QTest::mouseMove(&window, QPoint(700, 100));
    QCOMPARE(timeline->property("dragIndex").toInt(), 0);
    QCOMPARE(timeline->property("dropIndex").toInt(), 1);
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(700, 100));
    QCOMPARE(move.count(), 1);
    QCOMPARE(move.last().at(0).toInt(), 0);
    QCOMPARE(move.last().at(1).toInt(), 1);
    QCOMPARE(timeline->property("dragIndex").toInt(), -1);

    // The drawn playhead eases to a new position instead of jumping.
    timeline->setProperty("playheadMs", 4000);
    QVERIFY(timeline->property("shownMs").toDouble() < 4000.0);
    QTRY_VERIFY_WITH_TIMEOUT(qAbs(timeline->property("shownMs").toDouble() - 4000.0) < 1.0, 2000);

    // The playhead flag drags relative to where it was grabbed.
    scrub.clear();
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(410, 10));
    QTest::mouseMove(&window, QPoint(450, 10));
    QTest::mouseMove(&window, QPoint(490, 10));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(490, 10));
    QVERIFY(qAbs(scrub.last().first().toDouble() - 4800.0) < 20);

    // Arrow keys step by a second.
    scrub.clear();
    timeline->forceActiveFocus();
    QTest::keyClick(&window, Qt::Key_Right);
    QVERIFY(qAbs(scrub.last().first().toDouble() - 5000.0) < 1);

    // Ctrl + wheel zooms around the pointer.
    QWheelEvent wheel(QPointF(400, 100), window.mapToGlobal(QPointF(400, 100)), {}, QPoint(0, 120),
                      Qt::NoButton, Qt::ControlModifier, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(&window, &wheel);
    QVERIFY(timeline->property("zoom").toDouble() > 1.0);
}

void UiTests::toolControls()
{
    QQmlEngine engine;
    auto combo = createFromModule(engine, "ToolCombo");
    auto *comboItem = qobject_cast<QQuickItem *>(combo.get());
    QVERIFY(comboItem);
    comboItem->setWidth(240);
    comboItem->setProperty("model", QStringList{"MP4", "WebM", "GIF"});
    QCOMPARE(comboItem->property("currentText").toString(), QString("MP4"));

    auto check = createFromModule(engine, "ToolCheck");
    auto *checkItem = qobject_cast<QQuickItem *>(check.get());
    QVERIFY(checkItem);
    checkItem->setY(70);
    checkItem->setWidth(240);
    checkItem->setProperty("text", "Remove audio");

    QQuickWindow window;
    window.setGeometry(50, 50, 260, 200);
    comboItem->setParentItem(window.contentItem());
    checkItem->setParentItem(window.contentItem());
    window.show();
    QTest::qWait(100);

    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(20, 18));
    QVERIFY(comboItem->property("popup").value<QObject *>()->property("visible").toBool());
    QTest::keyClick(&window, Qt::Key_Escape);
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(20, 92));
    QVERIFY(checkItem->property("checked").toBool());

    comboItem->setProperty("textRole", "label");
    comboItem->setProperty("valueRole", "value");
    comboItem->setProperty("model", QVariantList{
        QVariantMap{{"label", "Merge PDFs"}, {"value", "merge"}},
        QVariantMap{{"label", "Rotate pages"}, {"value", "rotate"}}
    });
    comboItem->setProperty("currentIndex", 1);
    QCOMPARE(comboItem->property("currentText").toString(), QString("Rotate pages"));
    QCOMPARE(comboItem->property("currentValue").toString(), QString("rotate"));
}

void UiTests::studioNavigation()
{
    QQmlEngine engine;
    auto object = createFromModule(engine, "NavItem");
    auto *item = qobject_cast<QQuickItem *>(object.get());
    QVERIFY(item);
    item->setWidth(172);
    item->setHeight(43);
    item->setProperty("title", "GIF Studio");
    item->setProperty("iconName", "gif");
    item->setProperty("active", true);

    QQuickWindow window;
    window.setGeometry(50, 50, 172, 43);
    item->setParentItem(window.contentItem());
    window.show();
    QTest::qWait(100);

    const auto method = item->metaObject()->method(item->metaObject()->indexOfSignal("clicked()"));
    QVERIFY(method.isValid());
    QSignalSpy clicked(item, method);
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(80, 20));
    QCOMPARE(clicked.count(), 1);
    item->forceActiveFocus();
    QTest::keyClick(&window, Qt::Key_Return);
    QCOMPARE(clicked.count(), 2);

    auto progress = createFromModule(engine, "StudioProgress");
    QVERIFY(progress);
    progress->setProperty("value", 0.5);
    QCOMPARE(progress->property("value").toDouble(), 0.5);
}

void UiTests::toolInputs()
{
    QQmlEngine engine;
    auto stripObject = createFromModule(engine, "RangeStrip");
    auto *strip = qobject_cast<QQuickItem *>(stripObject.get());
    QVERIFY(strip);
    // 10 s across 500 px: 50 px per second; range 2 s – 6 s.
    strip->setWidth(500);
    strip->setHeight(72);
    strip->setProperty("durationMs", 10000);
    strip->setProperty("startMs", 2000);
    strip->setProperty("endMs", 6000);

    auto zoneObject = createFromModule(engine, "DropZone");
    auto *zone = qobject_cast<QQuickItem *>(zoneObject.get());
    QVERIFY(zone);
    zone->setY(100);
    zone->setWidth(500);
    zone->setHeight(200);

    QQuickWindow window;
    window.setGeometry(50, 50, 500, 300);
    strip->setParentItem(window.contentItem());
    zone->setParentItem(window.contentItem());
    window.show();
    QVERIFY(QTest::qWaitForWindowExposed(&window));

    QSignalSpy range(strip, signalOf(strip, "rangeRequested(double,double)"));
    QSignalSpy seek(strip, signalOf(strip, "seekRequested(double)"));
    QVERIFY(range.isValid() && seek.isValid());

    // Start handle sits at x = 100.
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(100, 45));
    QTest::mouseMove(&window, QPoint(120, 45));
    QTest::mouseMove(&window, QPoint(150, 45));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(150, 45));
    QVERIFY(range.count() > 0);
    QVERIFY(qAbs(range.last().at(0).toDouble() - 3000.0) < 50);
    QCOMPARE(range.last().at(1).toDouble(), 6000.0);

    // Dragging inside the range moves both ends.
    range.clear();
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(200, 45));
    QTest::mouseMove(&window, QPoint(220, 45));
    QTest::mouseMove(&window, QPoint(250, 45));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(250, 45));
    QVERIFY(qAbs(range.last().at(0).toDouble() - 3000.0) < 50);
    QVERIFY(qAbs(range.last().at(1).toDouble() - 7000.0) < 50);

    // Clicking outside the range seeks.
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(450, 45));
    QVERIFY(seek.count() > 0);
    QVERIFY(qAbs(seek.last().first().toDouble() - 9000.0) < 50);

    QSignalSpy browse(zone, signalOf(zone, "browseRequested()"));
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(250, 200));
    QCOMPARE(browse.count(), 1);

    // The playhead pin under the lane can be grabbed and dragged (y 48–72).
    strip->setProperty("positionMs", 5000);
    seek.clear();
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(254, 62));
    QVERIFY(strip->property("scrubbing").toBool());
    QTest::mouseMove(&window, QPoint(280, 62));
    QTest::mouseMove(&window, QPoint(304, 62));
    QVERIFY(qAbs(strip->property("shownMs").toDouble() - 6000.0) < 50);
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(304, 62));
    QVERIFY(seek.count() > 0);
    QVERIFY(qAbs(seek.last().first().toDouble() - 6000.0) < 50);
    QVERIFY(!strip->property("scrubbing").toBool());

    // Waveform mode (the audio trimmer): frames give way to the waveform, and
    // long files label handles in minutes.
    QVERIFY(!strip->property("waveMode").toBool());
    strip->setProperty("waveLoading", true);
    QVERIFY(strip->property("waveMode").toBool());
    strip->setProperty("durationMs", 125000);
    QVariant label;
    QVERIFY(QMetaObject::invokeMethod(strip, "label", Q_RETURN_ARG(QVariant, label), Q_ARG(QVariant, 83500)));
    QCOMPARE(label.toString(), QStringLiteral("1:23.5"));
}

void UiTests::updateCard()
{
    QQmlEngine engine;
    // Stand-in with AppUpdater's properties, so no network is involved.
    QQmlComponent fakeComponent(&engine);
    fakeComponent.setData(R"(import QtQuick
QtObject {
    property bool updateAvailable: true
    property bool canInstall: true
    property bool checking: false
    property bool downloading: false
    property bool ready: false
    property real progress: 0
    property string latestVersion: "0.2.0"
    property string currentVersion: "0.1.0"
    property string statusText: "Kadron 0.2.0 is available"
    property url releaseUrl: "https://example.org/releases"
    property int installs: 0
    property int restarts: 0
    signal changed()
    function install() { installs++ }
    function restartToUpdate() { restarts++ }
    function check() {}
})", QUrl("qrc:/fake-updater.qml"));
    std::unique_ptr<QObject> updater(fakeComponent.create());
    QVERIFY(updater);

    auto object = createFromModule(engine, "UpdateCard");
    auto *card = qobject_cast<QQuickItem *>(object.get());
    QVERIFY(card);
    card->setWidth(164);
    card->setProperty("updater", QVariant::fromValue(updater.get()));
    QVERIFY(card->property("offering").toBool());

    QQuickWindow window;
    window.setGeometry(50, 50, 188, 260);
    card->setParentItem(window.contentItem());
    window.show();
    QVERIFY(QTest::qWaitForWindowExposed(&window));
    QTest::qWait(700);

    auto *button = card->findChild<QQuickItem *>("updateButton");
    QVERIFY(button && button->isVisible());
    QCOMPARE(button->property("text").toString(), QString("Update"));
    const auto center = [button] { return button->mapToScene(QPointF(button->width() / 2, button->height() / 2)).toPoint(); };
    QTest::mouseClick(&window, Qt::LeftButton, {}, center());
    QCOMPARE(updater->property("installs").toInt(), 1);

    // While downloading the button gives way to progress.
    updater->setProperty("downloading", true);
    updater->setProperty("progress", 0.42);
    QVERIFY(!button->isVisible());
    updater->setProperty("downloading", false);

    // A verified download restarts into the installer.
    updater->setProperty("ready", true);
    QCOMPARE(button->property("text").toString(), QString("Restart to update"));
    QSignalSpy restart(card, signalOf(card, "restartRequested()"));
    QVERIFY(restart.isValid());
    QTest::qWait(50);
    QTest::mouseClick(&window, Qt::LeftButton, {}, center());
    QCOMPARE(updater->property("restarts").toInt(), 1);
    QCOMPARE(restart.count(), 1);

    // Portable copies are sent to the release page instead.
    updater->setProperty("ready", false);
    updater->setProperty("canInstall", false);
    QCOMPARE(button->property("text").toString(), QString("Open release"));

    // No update: the card folds away.
    updater->setProperty("updateAvailable", false);
    QVERIFY(!card->property("offering").toBool());
}

void UiTests::appearance()
{
    QQmlEngine engine;
    auto *prefs = engine.singletonInstance<QObject *>("Kadron", "Prefs");
    auto *theme = engine.singletonInstance<QObject *>("Kadron", "Theme");
    QVERIFY(prefs);
    QVERIFY(theme);
    prefs->setProperty("themeMode", "dark");
    prefs->setProperty("accent", "#c9f27a");
    QVERIFY(theme->property("dark").toBool());
    QCOMPARE(theme->property("window").value<QColor>(), QColor("#101317"));
    QCOMPARE(theme->property("accent").value<QColor>(), QColor("#c9f27a"));

    // Light surfaces, and the pale default accent deepened to stay readable.
    prefs->setProperty("themeMode", "light");
    QVERIFY(!theme->property("dark").toBool());
    QCOMPARE(theme->property("window").value<QColor>(), QColor("#eef1ec"));
    QVERIFY(theme->property("accent").value<QColor>().lightnessF() < QColor("#c9f27a").lightnessF());

    // A custom accent flows into the derived shades.
    prefs->setProperty("themeMode", "dark");
    prefs->setProperty("accent", "#7cc4ff");
    QCOMPARE(theme->property("accent").value<QColor>(), QColor("#7cc4ff"));
    const auto wash = theme->property("accentWash").value<QColor>();
    QVERIFY(wash.blue() > wash.red());

    // One remembered preview level; mute silences without losing it.
    auto object = createFromModule(engine, "VolumeControl");
    QVERIFY(object);
    prefs->setProperty("previewVolume", 0.4);
    prefs->setProperty("previewMuted", false);
    QCOMPARE(object->property("effectiveVolume").toDouble(), 0.4);
    prefs->setProperty("previewMuted", true);
    QCOMPARE(object->property("effectiveVolume").toDouble(), 0.0);
    QCOMPARE(prefs->property("previewVolume").toDouble(), 0.4);

    prefs->setProperty("previewMuted", false);
    prefs->setProperty("accent", "#c9f27a");
}

void UiTests::intro()
{
    QQmlEngine engine;
    auto intro = createFromModule(engine, "Intro");
    QVERIFY(intro);
    QVERIFY(engine.singletonInstance<QObject *>("Kadron", "Prefs")->property("startupIntro").toBool());

    // A skip before the app has loaded waits for it; then the intro leaves.
    QMetaObject::invokeMethod(intro.get(), "skip");
    QVERIFY(intro->property("skipped").toBool());
    QVERIFY(!intro->property("leaving").toBool());
    intro->setProperty("appReady", true);
    QVERIFY(intro->property("leaving").toBool());
}

QTEST_MAIN(UiTests)
#include "ui_tests.moc"
