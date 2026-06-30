# Changelog

## 1.0.0

Primera versión de **Worklog Calendar** en **Python / PyGObject** (GTK 4 +
libadwaita) para Ubuntu 24.04. Misma funcionalidad y UI que la versión en Vala.

### Añadido

- **Aplicación de escritorio** (Adw.Application) con ventana principal
  redimensionable.
- **Ventanita flotante** de 1000×700 abierta desde el **reloj blanco** de la
  barra superior (StatusNotifierItem + com.canonical.dbusmenu vía GDBus puro),
  con botón para saltar a la app completa.
- **Ejecución en segundo plano**: cerrar oculta las ventanas; salir sólo desde
  *clic derecho en el reloj → Salir* (o `Ctrl+Q`).
- **La planilla**: grilla semanal Cairo con modo 9h/24h, drag-to-create,
  clic-para-editar, mover y redimensionar bloques, duplicar.
- **Tres fuentes**: Jira, Clockify y combinado (día partido).
- **Anillos** de Sprint y Horas con animación de llenado.
- **Heatmap mensual** Clockify + Jira con navegación de mes.
- **Tabla de subtareas** con búsqueda, badges de estado y transiciones.
- **Sync Jira → Clockify** con deduplicación por solape.
- **Stores async** con `urllib` en un hilo + `GLib.idle_add` (sin librerías
  HTTP/JSON externas: todo es biblioteca estándar de Python).
- **Preferencias** completas (Adw.PreferencesWindow) sobre **GSettings**.
- **Instalación** con Meson + `install.sh`, esquema/desktop/iconos incluidos.
- Documentación en `docs/` (configuración, Jira, Clockify).
