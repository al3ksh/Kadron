#include <QMetaMethod>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

class UiTests final : public QObject
{
    Q_OBJECT

private slots:
    void timelineInteractions();
    void toolControls();
    void studioNavigation();
};

void UiTests::timelineInteractions()
{
    QQmlEngine engine;
    QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(KADRON_SOURCE_DIR) + "/qml/Timeline.qml"));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    std::unique_ptr<QObject> object(component.create());
    auto *timeline = qobject_cast<QQuickItem *>(object.get());
    QVERIFY(timeline);
    timeline->setWidth(800);
    timeline->setHeight(146);
    timeline->setProperty("durationMs", 10000);
    timeline->setProperty("inMs", 2000);
    timeline->setProperty("outMs", 8000);
    timeline->setProperty("playheadMs", 2000);

    QQuickWindow window;
    window.setGeometry(50, 50, 800, 146);
    timeline->setParentItem(window.contentItem());
    window.show();
    QTest::qWait(100);

    const auto signal = [timeline](const char *name) {
        const auto index = timeline->metaObject()->indexOfSignal(name);
        return index < 0 ? QMetaMethod() : timeline->metaObject()->method(index);
    };
    const auto seekMethod = signal("seekRequested(double)");
    const auto inMethod = signal("inRequested(double)");
    const auto moveMethod = signal("moveRequested(double)");
    QVERIFY(seekMethod.isValid());
    QVERIFY(inMethod.isValid());
    QVERIFY(moveMethod.isValid());
    QSignalSpy seekSpy(timeline, seekMethod);
    QSignalSpy inSpy(timeline, inMethod);
    QSignalSpy moveSpy(timeline, moveMethod);

    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(400, 16));
    QVERIFY(seekSpy.count() > 0);
    QVERIFY(qAbs(seekSpy.last().first().toDouble() - 5000.0) < 100);

    seekSpy.clear();
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(300, 90));
    QVERIFY(seekSpy.count() > 0);

    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(160, 90));
    QTest::mouseMove(&window, QPoint(210, 90));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(210, 90));
    QVERIFY(inSpy.count() > 0);

    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(400, 92));
    QTest::mouseMove(&window, QPoint(450, 92));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(450, 92));
    QVERIFY(moveSpy.count() > 0);

    timeline->setProperty("playheadMs", 5000);
    seekSpy.clear();
    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(400, 15));
    QTest::mouseMove(&window, QPoint(480, 15));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(480, 15));
    QVERIFY(seekSpy.count() > 0);
    QVERIFY(qAbs(seekSpy.last().first().toDouble() - 6000.0) < 100);

    timeline->setProperty("playheadMs", 5000);
    seekSpy.clear();
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(400, 15));
    QTest::keyClick(&window, Qt::Key_Right);
    QVERIFY(seekSpy.count() > 0);
    QVERIFY(qAbs(seekSpy.last().first().toDouble() - 6000.0) < 100);
}

void UiTests::toolControls()
{
    QQmlEngine engine;
    QQmlComponent comboComponent(&engine, QUrl::fromLocalFile(QStringLiteral(KADRON_SOURCE_DIR) + "/qml/ToolCombo.qml"));
    QVERIFY2(comboComponent.isReady(), qPrintable(comboComponent.errorString()));
    std::unique_ptr<QObject> combo(comboComponent.create());
    auto *comboItem = qobject_cast<QQuickItem *>(combo.get());
    QVERIFY(comboItem);
    comboItem->setWidth(240);
    comboItem->setProperty("model", QStringList{"MP4", "WebM", "GIF"});
    QCOMPARE(comboItem->property("currentText").toString(), QString("MP4"));

    QQmlComponent checkComponent(&engine, QUrl::fromLocalFile(QStringLiteral(KADRON_SOURCE_DIR) + "/qml/ToolCheck.qml"));
    QVERIFY2(checkComponent.isReady(), qPrintable(checkComponent.errorString()));
    std::unique_ptr<QObject> check(checkComponent.create());
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
    QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(KADRON_SOURCE_DIR) + "/qml/NavItem.qml"));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    std::unique_ptr<QObject> object(component.create());
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

    QQmlComponent progressComponent(&engine, QUrl::fromLocalFile(QStringLiteral(KADRON_SOURCE_DIR) + "/qml/StudioProgress.qml"));
    QVERIFY2(progressComponent.isReady(), qPrintable(progressComponent.errorString()));
    std::unique_ptr<QObject> progress(progressComponent.create());
    QVERIFY(progress);
    progress->setProperty("value", 0.5);
    QCOMPARE(progress->property("value").toDouble(), 0.5);
}

QTEST_MAIN(UiTests)
#include "ui_tests.moc"
