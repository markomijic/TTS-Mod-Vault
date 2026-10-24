# Primeros pasos

TTS Mod Vault lee las carpetas `Mods` y `Saves` de Tabletop Simulator, muestra cada mod, partida guardada y objeto guardado con el estado de sus archivos de recursos y te permite descargar los archivos que faltan, crear copias de seguridad `.ttsmod` y restaurarlas.

- Define las carpetas en Ajustes → Carpetas. La carpeta de copias es opcional, pero es necesaria para recordar el estado de las copias entre sesiones.
- La biblioteca se indexa al iniciar; pulsa Actualizar en la barra lateral después de cambiar archivos fuera de la aplicación. "Vaciar la caché de Vault" vuelve a leer todos los archivos JSON.
- Mods, Partidas guardadas, Objetos guardados y Copias son pestañas encima de la lista. Los objetos guardados aparecen si se activan en Ajustes → Funciones, y Copias cuando hay una carpeta de copias definida.

# Biblioteca

- Haz clic en un mod para ver sus recursos y acciones
- Haz clic derecho en un mod para ver más acciones (descargar, hacer copia, abrir carpeta, renombrar, eliminar, ...)
- Ctrl+clic (Cmd+clic en macOS) para seleccionar varios mods para acciones en lote
- Pasa el cursor sobre el icono de copia de un mod para ver la fecha de la copia y el número de recursos
- Pasa el cursor sobre el selector de tipo para ver cuántos mods, partidas guardadas y objetos guardados hay
- Busca, ordena y filtra con la barra de herramientas; las acciones en lote respetan el texto de búsqueda y los filtros
- Teclado: Ctrl+F enfoca la búsqueda, F5 actualiza, Esc quita la selección, Supr elimina el mod seleccionado tras una confirmación

# Mod seleccionado

El panel derecho muestra los recursos del mod seleccionado agrupados por tipo. Colores de las URL:

- Rojo: falta el archivo del recurso
- Verde: el archivo del recurso está descargado
- Naranja: una comprobación de URL marcó la URL como no válida
- Resaltada: la última URL en la que hiciste clic

Acciones:

- Haz clic izquierdo o derecho en una URL para ver las opciones (abrir, copiar, descargar, reemplazar, eliminar el archivo)
- Haz doble clic en la miniatura de un PDF para abrir el archivo
- Descargar todo: descarga todos los archivos de recursos que faltan. Los archivos que sigan faltando después se comprueban: el diálogo "Resultados de la comprobación de la descarga" muestra los dominios inaccesibles y las URL que no funcionan. Puedes desactivarlo en Ajustes → Red → Comprobar los archivos que faltan tras las descargas
- "Faltan 3, 2 no válidas" en una tarjeta: faltan 3 archivos y una comprobación de URL encontró que 2 de sus URL no funcionan, así que esos archivos no se pueden descargar
- Copia de seguridad: crea una copia a partir de los archivos de recursos descargados
- Los recursos de audio se pueden excluir de forma general en Ajustes → Funciones y cambiar para cada mod desde su menú contextual

# Copias de seguridad

- Las copias son archivos `.ttsmod` que contienen el JSON del mod, su imagen y todos los archivos de recursos descargados.
- El estado de la copia la compara con el mod: al día, desactualizada (el JSON cambió después de la copia) o número de recursos distinto.
- Importar copias, en la barra lateral, restaura archivos en la carpeta Mods. Importar JSON añade un mod desde un archivo JSON.
- Las copias en lote permiten omitir, reemplazar y reemplazar si está desactualizada, con la opción de eliminar después los archivos del mod.

# Actualizar URL

La función Actualizar URL reemplaza el principio de las URL, o incluso URL completas, del "Prefijo antiguo" por el "Prefijo nuevo".

Puedes introducir varios prefijos antiguos separándolos con el símbolo `|` (barra vertical). En Ajustes → Ajustes predefinidos de URL puedes crear predefinidos que luego se ofrecen en el diálogo Actualizar URL.

Con un solo prefijo antiguo:

- Prefijo antiguo: `http://pastebin.com/raw.php?i=`
- Prefijo nuevo: `https://pastebin.com/raw/`

Si tu mod contiene `http://pastebin.com/raw.php?i=1234` y `http://pastebin.com/raw.php?i=example`, se actualizarán a `https://pastebin.com/raw/1234` y `https://pastebin.com/raw/example`.

Con varios prefijos antiguos:

- Prefijos antiguos: `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- Prefijo nuevo: `https://pastebin.com/raw/`

Si tu mod contiene `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` y `http://pastebin.com/example2`, se actualizarán a `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` y `https://pastebin.com/raw/example2`.

# Workshop

- Descarga mods del Workshop de Steam por ID o URL desde la barra lateral; puedes introducir varios ID a la vez.
- Actualizar desde el Workshop vuelve a descargar el JSON de un mod que ya existe. La opción de forzar sobrescribe un archivo local más reciente.

# Solución de problemas

- El panel de registro bajo la lista anota cada operación con sus errores; expándelo para filtrar por nivel y origen, buscar, copiar entradas o borrarlo. Haz clic en una entrada para seleccionar su mod.
- El archivo de registro `vault.log` está junto a la base de datos. Ábrelo desde la cabecera del panel de registro o desde la pestaña Acerca de; adjúntalo a los informes de errores.
- ¿No aparece nada tras cambiar una carpeta? Pulsa Actualizar. ¿Sigue sin aparecer? Revisa las rutas de las carpetas en Ajustes → Carpetas y las subcarpetas excluidas.
- ¿Fallan descargas de URL que funcionan cuando hay muchas a la vez? Baja las descargas simultáneas en Ajustes → Red.
- Las comprobaciones de URL y la comprobación tras una descarga primero prueban si se puede acceder a cada dominio. Las URL de un dominio inaccesible (caído o bloqueado en tu red) no se marcan como no válidas, y una comprobación de URL con un dominio así no se guarda. Ajustes → Red → Comprobar todos los dominios de mods y partidas guardadas prueba cada dominio que usan tus mods y partidas guardadas.
