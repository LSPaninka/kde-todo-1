# qml-harness

Render offscreen del `main.qml` real contra módulos KDE simulados (`fake/`), para
verificar el port a Plasma 6 sin tener Plasma instalado.

```bash
python3 -m venv .venv && .venv/bin/pip install PySide6-Essentials   # y: sudo apt install libegl1
.venv/bin/python tools/qml-harness/run.py package /tmp/capturas
```

- Genera el singleton `Plasmoid` desde los valores por defecto de `package/contents/config/main.xml`.
- Sirve un Jira falso en `127.0.0.1` para poblar `JiraView`.
- Hace clics, rueda y diálogos con eventos reales y captura PNGs.
- Imprime los `WARNING` del motor/código (objetivo: 0). Los `console.warn` deliberados de las stores
  (credenciales faltantes, HTTP sin TLS…) se cuentan aparte.
- Las páginas de configuración que usan `Kirigami.FormData` (adjunta, en C++) se omiten; para esas, `qmllint`.
