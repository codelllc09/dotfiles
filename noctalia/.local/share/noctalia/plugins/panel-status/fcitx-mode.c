#include <gio/gio.h>
#include <stdio.h>

static GVariant *read_fcitx(GDBusConnection *bus, const char *path,
                           const char *interface, const char *method,
                           const GVariantType *result_type)
{
    return g_dbus_connection_call_sync(
        bus, "org.fcitx.Fcitx5", path, interface, method, NULL, result_type,
        G_DBUS_CALL_FLAGS_NO_AUTO_START, 500, NULL, NULL);
}

static const char *input_mode(GDBusConnection *bus)
{
    g_autoptr(GVariant) method = read_fcitx(
        bus, "/controller", "org.fcitx.Fcitx.Controller1",
        "CurrentInputMethod", G_VARIANT_TYPE("(s)"));
    if (!method)
        return "—";

    const char *engine;
    g_variant_get(method, "(&s)", &engine);
    if (g_str_has_prefix(engine, "keyboard-"))
        return "EN";
    if (!g_str_equal(engine, "rime"))
        return "—";

    g_autoptr(GVariant) mode = read_fcitx(
        bus, "/rime", "org.fcitx.Fcitx.Rime1", "IsAsciiMode",
        G_VARIANT_TYPE("(b)"));
    if (!mode)
        return "—";

    gboolean ascii;
    g_variant_get(mode, "(b)", &ascii);
    return ascii ? "EN" : "中";
}

static void refresh(GDBusConnection *bus, const char **last_mode)
{
    const char *mode = input_mode(bus);
    if (g_strcmp0(mode, *last_mode) != 0) {
        *last_mode = mode;
        puts(mode);
        fflush(stdout);
    }
}

static void status_changed(GDBusConnection *bus,
                           G_GNUC_UNUSED const char *sender,
                           G_GNUC_UNUSED const char *path,
                           G_GNUC_UNUSED const char *interface,
                           G_GNUC_UNUSED const char *signal,
                           G_GNUC_UNUSED GVariant *parameters,
                           gpointer data)
{
    refresh(bus, data);
}

int main(void)
{
    g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (!bus)
        return 1;

    const char *last_mode = NULL;
    // The tray emits NewIcon when Rime's internal Latin mode changes.
    g_dbus_connection_signal_subscribe(
        bus, NULL, "org.kde.StatusNotifierItem", "NewIcon", "/StatusNotifierItem",
        NULL, G_DBUS_SIGNAL_FLAGS_NONE, status_changed, &last_mode, NULL);
    g_dbus_connection_signal_subscribe(
        bus, "org.kde.StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
        "StatusNotifierItemRegistered", "/StatusNotifierWatcher", NULL,
        G_DBUS_SIGNAL_FLAGS_NONE, status_changed, &last_mode, NULL);
    g_dbus_connection_signal_subscribe(
        bus, "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
        "/org/freedesktop/DBus", "org.fcitx.Fcitx5", G_DBUS_SIGNAL_FLAGS_NONE,
        status_changed, &last_mode, NULL);

    refresh(bus, &last_mode);
    g_autoptr(GMainLoop) loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(loop);
    return 0;
}
