#!/usr/bin/env bash
# =============================================================================
#  mc-setup.sh  -  Interactive Minecraft (Java Edition) server installer
#
#  Asks you a few questions in a terminal menu, then:
#    * downloads Vanilla (Mojang) or PaperMC from the official APIs
#    * optionally puts a Velocity proxy in front of it (modern forwarding)
#    * sets "online mode" (premium Microsoft account login) on or off
#    * makes sure a suitable Java is available (downloads Temurin if needed)
#    * sets up a tunnel (playit.gg / ngrok) or helps with port forwarding
#    * writes server.properties, eula.txt and ready-to-use start scripts
#
#  Usage:   bash mc-setup.sh            (menus use whiptail/dialog if present)
#           MCS_UI=text bash mc-setup.sh   (force plain text prompts)
#           bash mc-setup.sh --help
# =============================================================================
# --- needs bash 4.3+. macOS ships bash 3.2, so look for a newer one (Homebrew) and restart with it.
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 3 ]; }; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash; do
    if [ -x "$_b" ] && "$_b" -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]; }' 2>/dev/null; then
      exec "$_b" "$0" "$@"
    fi
  done
  echo "This script needs a newer bash than the one on this computer (you have ${BASH_VERSION:-an old one})."
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "On a Mac: double-click mc-setup.command - it installs what is needed - or run:  brew install bash"
  else
    echo "Please install bash 4.3 or newer."
  fi
  exit 1
fi
set -Eeuo pipefail

OS_NAME=$(uname -s)
IS_MAC=0; [[ "$OS_NAME" == "Darwin" ]] && IS_MAC=1
if (( IS_MAC )); then   # Homebrew and our own tools folder are not on PATH inside some launchers
  PATH="$PATH:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.mc-setup/bin"; export PATH
fi

SCRIPT_VERSION="1.1.0"
MOJANG_MANIFEST="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
PAPER_API="https://fill.papermc.io/v3/projects"
ADOPTIUM_API="https://api.adoptium.net/v3/binary/latest"
NGROK_BASE="https://bin.equinox.io/c/bNyj1mQVY4c"
UA="mc-setup.sh/${SCRIPT_VERSION}"

# ============================================================================
#  POPULAR PLUGINS & MODS  -  the pick-list is built from these tables.
#  To add one, add a line:  "modrinth-slug|Name shown|Short description"
#  (the slug is the end of its Modrinth link: modrinth.com/plugin/<slug>).
#  You can also add lines without editing this script: put them in a file called
#  plugins.list (for Paper plugins) or mods.list (for Fabric/Forge/NeoForge mods)
#  next to this script or in the folder you run it from. '#' starts a comment.
#  Only entries that work with your chosen Minecraft version are shown.
# ============================================================================
PLUGIN_CATALOG=(
  "essentialsx|EssentialsX|Homes, warps, kits and ~100 everyday commands"
  "luckperms|LuckPerms|Ranks and permissions"
  "worldedit|WorldEdit|Build tool: copy, paste and edit big areas"
  "fastasyncworldedit|FastAsyncWorldEdit|Faster WorldEdit for huge edits (use instead of WorldEdit)"
  "worldguard|WorldGuard|Protect regions from griefing"
  "coreprotect|CoreProtect|Log everything and roll back griefing"
  "griefprevention|GriefPrevention|Players claim land with a golden shovel"
  "vaultunlocked|VaultUnlocked|Economy and permissions bridge (the maintained Vault)"
  "placeholderapi|PlaceholderAPI|Placeholders many other plugins use"
  "chunky|Chunky|Pre-generate the world so exploring doesn't lag"
  "chunkyborder|Chunky Border|Nice world border"
  "geyser|Geyser|Let Bedrock players (phone, console) join"
  "floodgate|Floodgate|Bedrock players join without a Java account"
  "viaversion|ViaVersion|Newer Minecraft versions can join"
  "viabackwards|ViaBackwards|Older Minecraft versions can join"
  "viarewind|ViaRewind|Very old clients (1.8) can join"
  "simple-voice-chat|Simple Voice Chat|Talk to nearby players (proximity voice)"
  "dynmap|Dynmap|Live map of your world in a web browser"
  "bluemap|BlueMap|Pretty 3D web map"
  "skinsrestorer|SkinsRestorer|Show real skins on offline-mode servers"
  "tab-was-taken|TAB|Custom player list, name tags and scoreboards"
  "decentholograms|DecentHolograms|Floating text holograms"
  "huskhomes|HuskHomes|Homes, warps and teleport requests"
  "multiverse-core|Multiverse-Core|Run several worlds on one server"
  "grimac|Grim Anticheat|Stops common cheats"
  "libertybans|LibertyBans|Bans, mutes and warnings"
  "quickshop-hikari|QuickShop-Hikari|Player chest shops"
  "chestshop|ChestShop|Sign-based shops"
  "betterstructures|BetterStructures|More structures to find in the world"
)
MOD_CATALOG=(
  "lithium|Lithium|Big server speed-up, no gameplay changes"
  "ferrite-core|FerriteCore|Uses much less memory"
  "c2me-fabric|C2ME|Faster chunk loading and generation"
  "krypton|Krypton|Faster networking"
  "vmp-fabric|Very Many Players|Helps servers with lots of players"
  "no-chat-reports|No Chat Reports|Turns off chat reporting / signing"
  "spark|spark|Performance profiler (find what causes lag)"
  "simple-voice-chat|Simple Voice Chat|Talk to nearby players (proximity voice)"
  "luckperms|LuckPerms|Ranks and permissions"
  "worldedit|WorldEdit|Build tool: copy, paste and edit big areas"
  "chunky|Chunky|Pre-generate the world so exploring doesn't lag"
  "bluemap|BlueMap|Pretty 3D web map"
  "dynmap|Dynmap|Live map of your world in a web browser"
  "essential-commands|Essential Commands|Home, warp and teleport commands"
  "ledger|Ledger|Log and roll back griefing"
  "universal-graves|Universal Graves|Keep your stuff in a grave when you die"
  "styled-chat|Styled Chat|Coloured and formatted chat"
  "carpet|Carpet|Technical / redstone tweaks"
  "lootr|Lootr|Every player gets their own loot in chests"
)

# ============================================================================
#  LANGUAGES. Text is looked up by its English wording; anything missing falls
#  back to English. To add a language: make a file  lang/<code>.txt  next to this
#  script with lines  English text<TAB>translation  (see the blocks below), then
#  run with  MCS_LANG=<code>  (or pick it from the list).
# ============================================================================
declare -A TR=()
BOX_OPEN=0
for_each_lang() { printf '%s\n' en es fr de pt ru zh ja ko hi ar he tr it; }
lang_data_es() { cat <<'EOF'
Let's set up your Minecraft server	Vamos a crear tu servidor de Minecraft
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	Usa las flechas y Enter. Pulsa Ctrl+C para salir en cualquier momento.
Nothing is installed until you confirm at the end.	No se instala nada hasta que lo confirmes al final.
How do you want to set up?	¿Cómo quieres configurarlo?
Simple - a few easy questions, everything else is chosen for you	Simple: pocas preguntas fáciles, lo demás se elige por ti
Advanced - choose every option yourself	Avanzado: elige todas las opciones tú mismo
What do you want to call your server?	¿Cómo quieres llamar a tu servidor?
Where should your server be saved? A new folder with your server's name is created there.	¿Dónde guardar tu servidor? Se crea allí una carpeta nueva con su nombre.
Next to this script (recommended)	Junto a este script (recomendado)
On my Desktop	En mi Escritorio
In my Documents folder	En mi carpeta Documentos
Somewhere else (type a folder)	Otro lugar (escribe una carpeta)
Somewhere else (browse or type a folder)	Otro lugar (examinar o escribir una carpeta)
Your server will be installed in:	Tu servidor se instalará en:
Yes, use this folder	Sí, usar esta carpeta
No, pick another place	No, elegir otro lugar
Which kind of server do you want?	¿Qué tipo de servidor quieres?
Standard (recommended) - fast, and you can add plugins later	Estándar (recomendado): rápido y puedes añadir plugins después
Pure Minecraft - exactly like the official game	Minecraft puro: exactamente como el juego oficial
How will your friends join?	¿Cómo se unirán tus amigos?
Over the internet - easiest, no router settings (free)	Por internet: lo más fácil, sin tocar el router (gratis)
Over the internet using my router (port forwarding)	Por internet usando mi router (redirección de puertos)
Only people on my home Wi-Fi	Solo personas en mi Wi-Fi de casa
Does everyone who will join own Minecraft (a paid Microsoft account)?	¿Todos los que se unan tienen Minecraft (cuenta Microsoft de pago)?
YES = safest, recommended.	SÍ = lo más seguro, recomendado.
NO  = anyone can join with any name (only for friends you trust).	NO = cualquiera puede entrar con cualquier nombre (solo para amigos de confianza).
Yes	Sí
No	No
Finding the newest version ...	Buscando la versión más reciente ...
Want to change more things (server message, icon, mods, whitelist, world...)?	¿Quieres cambiar más cosas (mensaje, icono, mods, lista blanca, mundo...)?
Most people choose No - you can still do that later.	La mayoría elige No; puedes hacerlo más tarde.
Minecraft EULA	EULA de Minecraft
To run a server you must agree to the Minecraft End User License Agreement:	Para ejecutar un servidor debes aceptar el Contrato de Licencia de Usuario Final de Minecraft:
Do you agree to the EULA?	¿Aceptas el EULA?
Summary	Resumen
Install now?	¿Instalar ahora?
Installing your Minecraft server	Instalando tu servidor de Minecraft
Step 1 of 4 - Checking Java	Paso 1 de 4: comprobando Java
Step 2 of 4 - Downloading Minecraft (this can take a minute)	Paso 2 de 4: descargando Minecraft (puede tardar un minuto)
Step 3 of 4 - Setting up internet access	Paso 3 de 4: configurando el acceso a internet
Step 4 of 4 - Finishing up	Paso 4 de 4: terminando
Your server is ready	Tu servidor está listo
To start your server, run:	Para iniciar tu servidor, ejecuta:
To stop it, type  stop  in the server window.	Para detenerlo, escribe  stop  en la ventana del servidor.
Friends join with:	Tus amigos entran con:
Note: anyone can join with any name. Only share the address with people you trust.	Nota: cualquiera puede entrar con cualquier nombre. Comparte la dirección solo con gente de confianza.
(Your playit.gg address. Keep playit running while you play.)	(Tu dirección de playit.gg. Mantén playit abierto mientras juegas.)
(Only on the same Wi-Fi.)	(Solo en el mismo Wi-Fi.)
Start the server now?	¿Iniciar el servidor ahora?
All set - have fun!	Todo listo, ¡a divertirse!
Setup cancelled. Nothing was installed.	Configuración cancelada. No se instaló nada.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	¿Configurar ahora tu túnel gratuito de playit.gg con una guía paso a paso? (unos 10 minutos; también puedes hacerlo luego)
playit.gg tunnel	Túnel playit.gg
Name:	Nombre:
Type:	Tipo:
Friends:	Amigos:
Accounts:	Cuentas:
Memory:	Memoria:
Folder:	Carpeta:
Standard	Estándar
Pure Minecraft	Minecraft puro
over the internet (free tunnel)	por internet (túnel gratuito)
over the internet (router port forwarding)	por internet (redirección de puertos)
home Wi-Fi only	solo Wi-Fi de casa
everyone needs a Minecraft account	todos necesitan una cuenta de Minecraft
anyone can join with any name	cualquiera puede entrar con cualquier nombre
Press Enter to close	Pulsa Enter para cerrar
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	No estoy seguro de que esta ventana pueda mostrar este idioma. Si ves cuadrados o ? tras elegirlo, reinicia y elige inglés (Windows Terminal de Microsoft Store funciona mejor).
Use this language	Usar este idioma
Use English instead	Usar inglés en su lugar
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	Esta terminal no está en UTF-8, así que este idioma puede verse mal (cuadrados o ?). ¿Continuar en inglés?
Use English	Usar inglés
Try it anyway	Probar de todos modos
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	Consejo: si ves cuadrados en lugar de letras, ejecuta de nuevo con  -Lang en  o usa Windows Terminal.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	Consejo: si ves cuadrados en lugar de letras, ejecuta de nuevo con  --lang en  o usa una terminal con una fuente compatible.
none	ninguno
plugins	plugins
mods	mods
Back	Atrás
Customise your server. Pick a category; choose 'done' when finished.	Personaliza tu servidor. Elige una categoría; elige «listo» al terminar.
Server name: {0}	Nombre del servidor: {0}
Server list message with colours: {0}	Mensaje de la lista de servidores con colores: {0}
Server icon: {0}	Icono del servidor: {0}
Mods: {0} queued	Mods: {0} en cola
Plugins: {0} queued	Plugins: {0} en cola
Operators ({0}) and whitelist ({1})	Operadores ({0}) y lista blanca ({1})
World type, seed, structures, nether, hardcore	Tipo de mundo, semilla, estructuras, Nether, hardcore
PvP, command blocks, flying, mobs, spawn protection	PvP, bloques de comandos, vuelo, mobs, protección de aparición
View / simulation distance: {0} / {1}	Distancia de visión / simulación: {0} / {1}
Resource pack: {0}	Paquete de recursos: {0}
Any other server.properties setting ({0})	Cualquier otro ajuste de server.properties ({0})
Auto-restart on crash, backup script	Reinicio automático al fallar, script de copia de seguridad
Finished customising	Terminar de personalizar
Name of your server (e.g. Creeper Cove).	Nombre de tu servidor (p. ej. Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	Se usa en los títulos de ventana, el inicio automático, las copias de seguridad y, si no has puesto otro, como mensaje en la lista de servidores.
Server list message (MOTD).	Mensaje de la lista de servidores (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	Colores: &0 negro &1 azul oscuro &2 verde oscuro &3 aguamarina oscuro &4 rojo oscuro &5 morado &6 dorado
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 gris &8 gris oscuro &9 azul &a verde &b aguamarina &c rojo &d rosa &e amarillo &f blanco
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	Estilos:  &l negrita  &o cursiva  &n subrayado  &k aleatorio  &r restablecer
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	Usa \n para una segunda línea.    Ejemplo: &6&lMi Servidor\n&7¡Bienvenido!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	Icono del servidor: ruta de una imagen (png/jpg/gif...) o un enlace https://.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	Se convierte automáticamente a 64x64 píxeles (recortada al centro en cuadrado).
Leave empty for no icon.	Déjalo vacío para no usar icono.
File not found: {0}	Archivo no encontrado: {0}
Server icon created (64x64)	Icono del servidor creado (64x64)
Checking which popular {0} work with Minecraft {1} ...	Comprobando qué {0} populares funcionan con Minecraft {1} ...
[not updated for {0} yet - newest version will be tried]	[aún no actualizado para {0}: se probará la versión más reciente]
You already added everything in the popular list. Try the search option for more.	Ya añadiste todo lo de la lista popular. Prueba la búsqueda para ver más.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} es muy reciente, así que {1} plugin(s) aparecen como no actualizados. A menudo funcionan igual; elígelos si quieres probar.
Pick the {0} you want (Space = tick, Enter = done, A = all)	Elige los {0} que quieras (Espacio = marcar, Intro = listo, A = todos)
Added {0}	Añadido {0}
Add {0}  ({1} queued, loader: {2})	Añadir {0}  ({1} en cola, cargador: {2})
Add {0}  ({1} queued)	Añadir {0}  ({1} en cola)
Pick from a list of popular {0}	Elegir de una lista de {0} populares
Search Modrinth for {0} (compatible with {1})	Buscar {0} en Modrinth (compatibles con {1})
Add direct https:// links to .jar files	Añadir enlaces https:// directos a archivos .jar
Show / remove queued {0}	Ver / quitar {0} en cola
Done with {0}	Terminar con {0}
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Buscar en Modrinth ({0} para Minecraft {1}). Ejemplos: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	La búsqueda en Modrinth falló.
Nothing found for '{0}' that works with Minecraft {1}.	No se encontró nada para '{0}' que funcione con Minecraft {1}.
Results for '{0}':	Resultados para '{0}':
Added '{0}' (and any required dependencies).	Se añadió '{0}' (y las dependencias necesarias).
Direct https:// links to .jar files, separated by spaces.	Enlaces https:// directos a archivos .jar, separados por espacios.
Only use links from sources you trust - these files run on your server.	Usa solo enlaces de fuentes de confianza: estos archivos se ejecutan en tu servidor.
Skipping '{0}' (must start with https://)	Se omite '{0}' (debe empezar con https://)
Nothing queued yet.	Aún no hay nada en cola.
Back (keep everything)	Atrás (conservar todo)
Pick one to REMOVE from the install list:	Elige uno para QUITAR de la lista de instalación:
Skipping invalid name '{0}'	Se omite el nombre no válido '{0}'
Operators (admins). Minecraft usernames separated by spaces or commas.	Operadores (administradores). Nombres de usuario de Minecraft separados por espacios o comas.
Ops can use all commands.	Los operadores pueden usar todos los comandos.
Whitelist: only these players may join. Usernames separated by spaces or commas.	Lista blanca: solo estos jugadores pueden entrar. Nombres separados por espacios o comas.
Leave empty to keep the whitelist as chosen earlier.	Déjalo vacío para mantener la lista blanca elegida antes.
Could not look up '{0}' - add later with: whitelist add {0}	No se pudo buscar '{0}'; añádelo después con: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	No se pudo buscar '{0}'; añádelo después con: op {0}
World type:	Tipo de mundo:
Normal terrain	Terreno normal
Superflat	Superplano
Large biomes	Biomas grandes
Amplified (tall mountains)	Amplificado (montañas altas)
World seed (empty = random):	Semilla del mundo (vacío = aleatoria):
World folder name:	Nombre de la carpeta del mundo:
Generate structures (villages, strongholds, ...)?	¿Generar estructuras (aldeas, fortalezas, ...)?
Allow the Nether?	¿Permitir el Nether?
Hardcore mode? (one life, forced hard difficulty)	¿Modo hardcore? (una vida, dificultad difícil forzada)
Allow player-vs-player combat (PvP)?	¿Permitir combate entre jugadores (PvP)?
Enable command blocks?	¿Activar los bloques de comandos?
Allow flying (needed for some mods; otherwise flight is kicked)?	¿Permitir volar (necesario para algunos mods; si no, se expulsa por volar)?
Spawn animals?	¿Generar animales?
Spawn monsters?	¿Generar monstruos?
Spawn villagers?	¿Generar aldeanos?
Force everyone into the default game mode on every join?	¿Forzar a todos al modo de juego por defecto en cada entrada?
Spawn protection radius in blocks (0 = off):	Radio de protección de aparición en bloques (0 = desactivado):
Kick idle players after N minutes (0 = never):	Expulsar a jugadores inactivos tras N minutos (0 = nunca):
View distance in chunks (2-32). Lower = faster:	Distancia de visión en chunks (2-32). Menos = más rápido:
Simulation distance in chunks (2-32). Lower = faster:	Distancia de simulación en chunks (2-32). Menos = más rápido:
Please enter a number from {0} to {1}. Kept: {2}	Introduce un número de {0} a {1}. Se mantiene: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	Paquete de recursos del servidor: enlace https:// directo a un .zip (vacío = ninguno).
Players are offered it when they join. Its checksum is calculated at install time.	Se ofrece a los jugadores al entrar. Su suma de verificación se calcula durante la instalación.
That is not a link. Kept: {0}	Eso no es un enlace. Se mantiene: {0}
Kick players who decline the resource pack?	¿Expulsar a los jugadores que rechacen el paquete de recursos?
Any other server.properties setting as key=value, separated by spaces.	Cualquier otro ajuste de server.properties como clave=valor, separados por espacios.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	Ejemplo: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	Se omite '{0}' (usa clave=valor)
Restart the server automatically if it crashes?	¿Reiniciar el servidor automáticamente si se cae?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	¿Crear un script de copia de seguridad (comprime el mundo en la carpeta backups y conserva las 10 más recientes)?
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	Los cargadores de mods no se pueden combinar aquí con la configuración Velocity. (Los plugins de Paper sí: elige PaperMC.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla no admite mods por sí mismo. Elige un cargador de mods (sustituye al servidor Vanilla normal):
Fabric - lightweight, huge mod library (recommended)	Fabric: ligero, enorme biblioteca de mods (recomendado)
NeoForge - big content mods (1.20.2+)	NeoForge: mods de contenido grandes (1.20.2+)
Forge - classic loader (1.17+)	Forge: cargador clásico (1.17+)
Plain Vanilla, no mods	Vanilla normal, sin mods
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} no tiene versión de servidor para Minecraft {1}. Elige otro cargador u otra versión de Minecraft.
Modrinth lookup failed for '{0}'.	Falló la consulta de '{0}' en Modrinth.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	'{0}' aún no está marcado para {1}: se añadió su versión más reciente ({2}). Puede que aún funcione.
'{0}' has no download for {1} on this loader.	'{0}' no tiene descarga para {1} con este cargador.
Newest (recommended)	Más reciente (recomendada)
Type a specific older version	Escribir una versión anterior concreta
Which Minecraft version? (newest first)	¿Qué versión de Minecraft? (la más reciente primero)
Type the exact Minecraft version (e.g. 1.20.1):	Escribe la versión exacta de Minecraft (p. ej. 1.20.1):
That version is not available. Pick one from the list instead.	Esa versión no está disponible. Elige una de la lista.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	¿Pueden unirse también jugadores de Bedrock (móviles, consolas, Windows 10/11)?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	Entran con un complemento gratuito llamado Geyser, así que no necesitan cuenta de Java. Requiere el servidor Estándar (Paper), que se elige por ti. Los nombres de Bedrock llevan un punto delante (por ejemplo .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	¿Permitir también que se unan jugadores de Bedrock (Geyser + Floodgate)?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Los jugadores de Bedrock Edition (móviles, consolas, Windows 10/11) podrán entrar sin cuenta de Java. Requiere PaperMC y abre el puerto UDP 19132. Los nombres de Bedrock llevan un punto delante (por ejemplo .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Se cambió al servidor Estándar (PaperMC), porque el soporte de Bedrock lo necesita.
Downloading Geyser and Floodgate (Bedrock support) ...	Descargando Geyser y Floodgate (soporte de Bedrock) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Soporte de Bedrock instalado (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	también pueden entrar móviles, consolas y Windows 10/11
Bedrock players (phones, consoles, Windows 10/11) join with:	Los jugadores de Bedrock (móviles, consolas, Windows 10/11) entran con:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(En Minecraft Bedrock: Jugar > Servidores > Añadir servidor. Sus nombres llevan un punto delante, como .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	Consejo: detén primero el servidor (escribe  stop  en su ventana). Los cambios se leen al arrancar.
What do you want to change?	¿Qué quieres cambiar?
Server icon	Icono del servidor
Add plugins	Añadir plugins
Add mods	Añadir mods
Remove plugins	Quitar plugins
Remove mods	Quitar mods
Any other server.properties setting	Cualquier otro ajuste de server.properties
Change the Minecraft version (now {0})	Cambiar la versión de Minecraft (ahora {0})
Bedrock players: ON (Geyser + Floodgate)	Jugadores de Bedrock: SÍ (Geyser + Floodgate)
Bedrock players: off	Jugadores de Bedrock: no
Make a backup now	Hacer una copia de seguridad ahora
Saved.	Guardado.
All done. Start (or restart) your server to use the changes.	Listo. Inicia (o reinicia) tu servidor para usar los cambios.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	Cambiar la semilla, el tipo de mundo o el nombre de la carpeta solo afecta a un mundo NUEVO. Tu mundo actual no cambia.
Backup saved: {0}	Copia de seguridad guardada: {0}
Making a backup first ...	Haciendo primero una copia de seguridad ...
The backup failed - stopping here so nothing is lost.	La copia de seguridad falló: me detengo aquí para no perder nada.
Which server do you want to change?	¿Qué servidor quieres cambiar?
Pick another folder ...	Elegir otra carpeta ...
Type the folder of your server (the one that contains start-all):	Escribe la carpeta de tu servidor (la que contiene start-all):
That folder does not look like a server made by this tool.	Esa carpeta no parece un servidor creado con esta herramienta.
{0} file(s) placed in {1}	{0} archivo(s) colocados en {1}
Nothing is installed in this folder yet.	Aún no hay nada instalado en esta carpeta.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	Marca los que quieras QUITAR (se mueven a una carpeta llamada removed, no se borran)
Removed {0}	Quitado {0}
Fetching version list ...	Obteniendo la lista de versiones ...
Could not get the version list (is the internet working?).	No se pudo obtener la lista de versiones (¿funciona internet?).
That is the version you already have.	Esa es la versión que ya tienes.
Change Minecraft from {0} to {1}?	¿Cambiar Minecraft de {0} a {1}?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	Los mundos no pueden volver a una versión anterior, así que primero se hace una copia de seguridad completa. Después puede que haya que actualizar plugins y mods.
Now on Minecraft {0}	Ahora en Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	Si un plugin o mod deja de funcionar con la nueva versión, actualízalo o quítalo desde este menú. Para volver atrás, restaura la copia de seguridad de la carpeta backups.
This loader has no release for that version.	Este cargador no tiene versión para esa versión.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	El soporte de Bedrock está ACTIVADO. ¿Desactivarlo? (Geyser y Floodgate se mueven a una carpeta llamada removed.)
Bedrock support turned off.	Soporte de Bedrock desactivado.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	Aquí el soporte de Bedrock necesita un servidor PaperMC normal (no Velocity, Fabric ni Forge).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	¿Permitir que también se unan jugadores de Bedrock (móviles, consolas, Windows 10/11)?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Se añaden Geyser y Floodgate. Necesitan PaperMC. Los nombres de Bedrock llevan un punto delante (por ejemplo .Steve). Se usa el puerto UDP {0}.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	Tu servidor es Vanilla. ¿Cambiarlo a PaperMC (misma versión, mismo mundo)? Antes se hace una copia de seguridad completa.
PaperMC has no build for this version.	PaperMC no tiene compilación para esta versión.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Los jugadores de Bedrock necesitan que el puerto UDP {0} sea accesible. Con playit.gg ejecuta  bash mc-setup.sh --tunnel-guide  para añadir el túnel de Bedrock; con un router, redirige también el UDP {0}.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Los jugadores de Bedrock necesitan que el puerto UDP {0} sea accesible. Con playit.gg ejecuta  powershell -File mc-setup.ps1 -TunnelGuide  para añadir el túnel de Bedrock; con un router, redirige también el UDP {0}.
In my home folder	En mi carpeta personal
EOF
}
lang_data_fr() { cat <<'EOF'
Let's set up your Minecraft server	Configurons ton serveur Minecraft
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	Utilise les flèches et Entrée. Appuie sur Ctrl+C pour quitter à tout moment.
Nothing is installed until you confirm at the end.	Rien n'est installé avant que tu confirmes à la fin.
How do you want to set up?	Comment veux-tu procéder ?
Simple - a few easy questions, everything else is chosen for you	Simple : quelques questions faciles, le reste est choisi pour toi
Advanced - choose every option yourself	Avancé : choisis toutes les options toi-même
What do you want to call your server?	Comment veux-tu appeler ton serveur ?
Where should your server be saved? A new folder with your server's name is created there.	Où enregistrer ton serveur ? Un nouveau dossier à son nom y sera créé.
Next to this script (recommended)	À côté de ce script (recommandé)
On my Desktop	Sur mon Bureau
In my Documents folder	Dans mon dossier Documents
Somewhere else (type a folder)	Ailleurs (saisis un dossier)
Somewhere else (browse or type a folder)	Ailleurs (parcourir ou saisir un dossier)
Your server will be installed in:	Ton serveur sera installé dans :
Yes, use this folder	Oui, utiliser ce dossier
No, pick another place	Non, choisir un autre endroit
Which kind of server do you want?	Quel type de serveur veux-tu ?
Standard (recommended) - fast, and you can add plugins later	Standard (recommandé) : rapide, et tu pourras ajouter des plugins plus tard
Pure Minecraft - exactly like the official game	Minecraft pur : exactement comme le jeu officiel
How will your friends join?	Comment tes amis vont-ils rejoindre ?
Over the internet - easiest, no router settings (free)	Par Internet : le plus simple, sans réglages du routeur (gratuit)
Over the internet using my router (port forwarding)	Par Internet via mon routeur (redirection de ports)
Only people on my home Wi-Fi	Seulement les personnes sur mon Wi-Fi
Does everyone who will join own Minecraft (a paid Microsoft account)?	Tous ceux qui rejoindront possèdent-ils Minecraft (compte Microsoft payant) ?
YES = safest, recommended.	OUI = le plus sûr, recommandé.
NO  = anyone can join with any name (only for friends you trust).	NON = n'importe qui peut entrer avec n'importe quel nom (seulement pour des amis de confiance).
Yes	Oui
No	Non
Finding the newest version ...	Recherche de la dernière version ...
Want to change more things (server message, icon, mods, whitelist, world...)?	Veux-tu modifier d'autres choses (message, icône, mods, liste blanche, monde...) ?
Most people choose No - you can still do that later.	La plupart répondent Non ; tu pourras le faire plus tard.
Minecraft EULA	CLUF de Minecraft
To run a server you must agree to the Minecraft End User License Agreement:	Pour lancer un serveur, tu dois accepter le contrat de licence utilisateur final de Minecraft :
Do you agree to the EULA?	Acceptes-tu le CLUF ?
Summary	Résumé
Install now?	Installer maintenant ?
Installing your Minecraft server	Installation de ton serveur Minecraft
Step 1 of 4 - Checking Java	Étape 1 sur 4 : vérification de Java
Step 2 of 4 - Downloading Minecraft (this can take a minute)	Étape 2 sur 4 : téléchargement de Minecraft (cela peut prendre une minute)
Step 3 of 4 - Setting up internet access	Étape 3 sur 4 : configuration de l'accès Internet
Step 4 of 4 - Finishing up	Étape 4 sur 4 : finalisation
Your server is ready	Ton serveur est prêt
To start your server, run:	Pour démarrer ton serveur, lance :
To stop it, type  stop  in the server window.	Pour l'arrêter, tape  stop  dans la fenêtre du serveur.
Friends join with:	Tes amis rejoignent avec :
Note: anyone can join with any name. Only share the address with people you trust.	Note : n'importe qui peut entrer avec n'importe quel nom. Ne partage l'adresse qu'avec des personnes de confiance.
(Your playit.gg address. Keep playit running while you play.)	(Ton adresse playit.gg. Laisse playit ouvert pendant que tu joues.)
(Only on the same Wi-Fi.)	(Seulement sur le même Wi-Fi.)
Start the server now?	Démarrer le serveur maintenant ?
All set - have fun!	Tout est prêt, amuse-toi bien !
Setup cancelled. Nothing was installed.	Installation annulée. Rien n'a été installé.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	Configurer maintenant ton tunnel playit.gg gratuit avec un guide pas à pas ? (environ 10 minutes, tu peux aussi le faire plus tard)
playit.gg tunnel	Tunnel playit.gg
Name:	Nom :
Type:	Type :
Friends:	Amis :
Accounts:	Comptes :
Memory:	Mémoire :
Folder:	Dossier :
Standard	Standard
Pure Minecraft	Minecraft pur
over the internet (free tunnel)	par Internet (tunnel gratuit)
over the internet (router port forwarding)	par Internet (redirection de ports)
home Wi-Fi only	Wi-Fi de la maison uniquement
everyone needs a Minecraft account	tout le monde a besoin d'un compte Minecraft
anyone can join with any name	n'importe qui peut entrer avec n'importe quel nom
Press Enter to close	Appuie sur Entrée pour fermer
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	Je ne suis pas sûr que cette fenêtre puisse afficher cette langue. Si vous voyez des carrés ou des ? après l'avoir choisie, relancez et choisissez l'anglais (Windows Terminal du Microsoft Store fonctionne mieux).
Use this language	Utiliser cette langue
Use English instead	Utiliser l'anglais à la place
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	Ce terminal n'est pas en UTF-8, cette langue peut donc mal s'afficher (carrés ou ?). Continuer en anglais ?
Use English	Utiliser l'anglais
Try it anyway	Essayer quand même
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	Astuce : si vous voyez des carrés au lieu de lettres, relancez avec  -Lang en  ou utilisez Windows Terminal.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	Astuce : si vous voyez des carrés au lieu de lettres, relancez avec  --lang en  ou utilisez un terminal avec une police compatible.
none	aucun
plugins	plugins
mods	mods
Back	Retour
Customise your server. Pick a category; choose 'done' when finished.	Personnalisez votre serveur. Choisissez une catégorie ; choisissez « terminé » à la fin.
Server name: {0}	Nom du serveur : {0}
Server list message with colours: {0}	Message de la liste des serveurs avec couleurs : {0}
Server icon: {0}	Icône du serveur : {0}
Mods: {0} queued	Mods : {0} en attente
Plugins: {0} queued	Plugins : {0} en attente
Operators ({0}) and whitelist ({1})	Opérateurs ({0}) et liste blanche ({1})
World type, seed, structures, nether, hardcore	Type de monde, graine, structures, Nether, hardcore
PvP, command blocks, flying, mobs, spawn protection	PvP, blocs de commande, vol, mobs, protection du spawn
View / simulation distance: {0} / {1}	Distance d'affichage / de simulation : {0} / {1}
Resource pack: {0}	Pack de ressources : {0}
Any other server.properties setting ({0})	Tout autre réglage de server.properties ({0})
Auto-restart on crash, backup script	Redémarrage auto en cas de crash, script de sauvegarde
Finished customising	Terminer la personnalisation
Name of your server (e.g. Creeper Cove).	Nom de votre serveur (p. ex. Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	Utilisé pour les titres de fenêtre, le démarrage automatique, les sauvegardes et, si vous n'en avez pas défini, comme message dans la liste des serveurs.
Server list message (MOTD).	Message de la liste des serveurs (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	Couleurs : &0 noir &1 bleu foncé &2 vert foncé &3 cyan foncé &4 rouge foncé &5 violet &6 or
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 gris &8 gris foncé &9 bleu &a vert &b cyan &c rouge &d rose &e jaune &f blanc
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	Styles :  &l gras  &o italique  &n souligné  &k brouillé  &r réinitialiser
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	Utilisez \n pour une deuxième ligne.    Exemple : &6&lMon Serveur\n&7Bienvenue !
Server icon: path to an image (png/jpg/gif...) or an https:// link.	Icône du serveur : chemin d'une image (png/jpg/gif...) ou lien https://.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	Elle est convertie automatiquement en 64x64 pixels (recadrée au centre en carré).
Leave empty for no icon.	Laissez vide pour aucune icône.
File not found: {0}	Fichier introuvable : {0}
Server icon created (64x64)	Icône du serveur créée (64x64)
Checking which popular {0} work with Minecraft {1} ...	Vérification des {0} populaires compatibles avec Minecraft {1} ...
[not updated for {0} yet - newest version will be tried]	[pas encore mis à jour pour {0} - la version la plus récente sera essayée]
You already added everything in the popular list. Try the search option for more.	Vous avez déjà tout ajouté de la liste populaire. Essayez la recherche pour en trouver plus.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} est très récent, donc {1} plugin(s) sont marqués comme non mis à jour. Ils fonctionnent souvent quand même ; choisissez-les pour essayer.
Pick the {0} you want (Space = tick, Enter = done, A = all)	Choisissez les {0} voulus (Espace = cocher, Entrée = terminé, A = tout)
Added {0}	{0} ajouté
Add {0}  ({1} queued, loader: {2})	Ajouter des {0}  ({1} en attente, chargeur : {2})
Add {0}  ({1} queued)	Ajouter des {0}  ({1} en attente)
Pick from a list of popular {0}	Choisir dans une liste de {0} populaires
Search Modrinth for {0} (compatible with {1})	Rechercher des {0} sur Modrinth (compatibles avec {1})
Add direct https:// links to .jar files	Ajouter des liens https:// directs vers des fichiers .jar
Show / remove queued {0}	Afficher / retirer les {0} en attente
Done with {0}	Terminé avec les {0}
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Rechercher sur Modrinth ({0} pour Minecraft {1}). Exemples : worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	La recherche sur Modrinth a échoué.
Nothing found for '{0}' that works with Minecraft {1}.	Rien trouvé pour « {0} » qui fonctionne avec Minecraft {1}.
Results for '{0}':	Résultats pour « {0} » :
Added '{0}' (and any required dependencies).	« {0} » ajouté (avec les dépendances requises).
Direct https:// links to .jar files, separated by spaces.	Liens https:// directs vers des fichiers .jar, séparés par des espaces.
Only use links from sources you trust - these files run on your server.	N'utilisez que des liens de sources fiables : ces fichiers s'exécutent sur votre serveur.
Skipping '{0}' (must start with https://)	'{0}' ignoré (doit commencer par https://)
Nothing queued yet.	Rien en attente pour l'instant.
Back (keep everything)	Retour (tout conserver)
Pick one to REMOVE from the install list:	Choisissez-en un à RETIRER de la liste d'installation :
Skipping invalid name '{0}'	Nom invalide '{0}' ignoré
Operators (admins). Minecraft usernames separated by spaces or commas.	Opérateurs (admins). Pseudos Minecraft séparés par des espaces ou des virgules.
Ops can use all commands.	Les opérateurs peuvent utiliser toutes les commandes.
Whitelist: only these players may join. Usernames separated by spaces or commas.	Liste blanche : seuls ces joueurs peuvent rejoindre. Pseudos séparés par des espaces ou des virgules.
Leave empty to keep the whitelist as chosen earlier.	Laissez vide pour garder la liste blanche choisie plus tôt.
Could not look up '{0}' - add later with: whitelist add {0}	Impossible de retrouver « {0} » - ajoutez-le plus tard avec : whitelist add {0}
Could not look up '{0}' - add later with: op {0}	Impossible de retrouver « {0} » - ajoutez-le plus tard avec : op {0}
World type:	Type de monde :
Normal terrain	Terrain normal
Superflat	Superplat
Large biomes	Grands biomes
Amplified (tall mountains)	Amplifié (hautes montagnes)
World seed (empty = random):	Graine du monde (vide = aléatoire) :
World folder name:	Nom du dossier du monde :
Generate structures (villages, strongholds, ...)?	Générer des structures (villages, forteresses, ...) ?
Allow the Nether?	Autoriser le Nether ?
Hardcore mode? (one life, forced hard difficulty)	Mode hardcore ? (une seule vie, difficulté difficile imposée)
Allow player-vs-player combat (PvP)?	Autoriser les combats joueur contre joueur (PvP) ?
Enable command blocks?	Activer les blocs de commande ?
Allow flying (needed for some mods; otherwise flight is kicked)?	Autoriser le vol (nécessaire pour certains mods ; sinon le vol est sanctionné) ?
Spawn animals?	Faire apparaître des animaux ?
Spawn monsters?	Faire apparaître des monstres ?
Spawn villagers?	Faire apparaître des villageois ?
Force everyone into the default game mode on every join?	Forcer le mode de jeu par défaut pour tous à chaque connexion ?
Spawn protection radius in blocks (0 = off):	Rayon de protection du spawn en blocs (0 = désactivé) :
Kick idle players after N minutes (0 = never):	Expulser les joueurs inactifs après N minutes (0 = jamais) :
View distance in chunks (2-32). Lower = faster:	Distance d'affichage en chunks (2-32). Plus bas = plus rapide :
Simulation distance in chunks (2-32). Lower = faster:	Distance de simulation en chunks (2-32). Plus bas = plus rapide :
Please enter a number from {0} to {1}. Kept: {2}	Entrez un nombre de {0} à {1}. Conservé : {2}
Server resource pack: direct https:// link to a .zip (empty = none).	Pack de ressources du serveur : lien https:// direct vers un .zip (vide = aucun).
Players are offered it when they join. Its checksum is calculated at install time.	Il est proposé aux joueurs à leur connexion. Sa somme de contrôle est calculée à l'installation.
That is not a link. Kept: {0}	Ce n'est pas un lien. Conservé : {0}
Kick players who decline the resource pack?	Expulser les joueurs qui refusent le pack de ressources ?
Any other server.properties setting as key=value, separated by spaces.	Tout autre réglage de server.properties sous la forme clé=valeur, séparés par des espaces.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	Exemple : rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	'{0}' ignoré (utilisez clé=valeur)
Restart the server automatically if it crashes?	Redémarrer automatiquement le serveur en cas de crash ?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	Créer un script de sauvegarde (compresse le monde dans le dossier backups, garde les 10 plus récentes) ?
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	Les chargeurs de mods ne peuvent pas être combinés ici avec la configuration Velocity. (Les plugins Paper, si : choisissez PaperMC.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla ne gère pas les mods. Choisissez un chargeur de mods (il remplace le serveur Vanilla simple) :
Fabric - lightweight, huge mod library (recommended)	Fabric - léger, énorme bibliothèque de mods (recommandé)
NeoForge - big content mods (1.20.2+)	NeoForge - gros mods de contenu (1.20.2+)
Forge - classic loader (1.17+)	Forge - chargeur classique (1.17+)
Plain Vanilla, no mods	Vanilla simple, sans mods
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} n'a pas de version serveur pour Minecraft {1}. Choisissez un autre chargeur ou une autre version de Minecraft.
Modrinth lookup failed for '{0}'.	La recherche de « {0} » sur Modrinth a échoué.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	« {0} » n'est pas encore marqué pour {1} - sa version la plus récente ({2}) a été ajoutée. Elle peut quand même fonctionner.
'{0}' has no download for {1} on this loader.	« {0} » n'a pas de téléchargement pour {1} avec ce chargeur.
Newest (recommended)	La plus récente (recommandée)
Type a specific older version	Saisir une ancienne version précise
Which Minecraft version? (newest first)	Quelle version de Minecraft ? (la plus récente d'abord)
Type the exact Minecraft version (e.g. 1.20.1):	Saisissez la version exacte de Minecraft (p. ex. 1.20.1) :
That version is not available. Pick one from the list instead.	Cette version n'est pas disponible. Choisissez-en une dans la liste.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	Les joueurs Bedrock (téléphones, consoles, Windows 10/11) doivent-ils pouvoir rejoindre aussi ?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	Ils rejoignent via un module gratuit appelé Geyser, sans avoir besoin d'un compte Java. Il faut le serveur Standard (Paper), choisi pour vous. Les pseudos Bedrock ont un point devant (par exemple .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	Autoriser aussi les joueurs Bedrock (Geyser + Floodgate) ?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Les joueurs de Bedrock Edition (téléphones, consoles, Windows 10/11) pourront rejoindre sans compte Java. Il faut PaperMC et le port UDP 19132 est ouvert. Les pseudos Bedrock ont un point devant (par exemple .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Passage au serveur Standard (PaperMC), car la prise en charge de Bedrock en a besoin.
Downloading Geyser and Floodgate (Bedrock support) ...	Téléchargement de Geyser et Floodgate (prise en charge de Bedrock) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Prise en charge de Bedrock installée (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock :
phones, consoles and Windows 10/11 can join too	les téléphones, consoles et Windows 10/11 peuvent aussi rejoindre
Bedrock players (phones, consoles, Windows 10/11) join with:	Les joueurs Bedrock (téléphones, consoles, Windows 10/11) rejoignent avec :
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(Dans Minecraft Bedrock : Jouer > Serveurs > Ajouter un serveur. Leurs pseudos ont un point devant, comme .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	Astuce : arrêtez d'abord le serveur (tapez  stop  dans sa fenêtre). Les changements sont lus au démarrage.
What do you want to change?	Que voulez-vous modifier ?
Server icon	Icône du serveur
Add plugins	Ajouter des plugins
Add mods	Ajouter des mods
Remove plugins	Retirer des plugins
Remove mods	Retirer des mods
Any other server.properties setting	Tout autre réglage de server.properties
Change the Minecraft version (now {0})	Changer la version de Minecraft (actuellement {0})
Bedrock players: ON (Geyser + Floodgate)	Joueurs Bedrock : OUI (Geyser + Floodgate)
Bedrock players: off	Joueurs Bedrock : non
Make a backup now	Faire une sauvegarde maintenant
Saved.	Enregistré.
All done. Start (or restart) your server to use the changes.	Terminé. Démarrez (ou redémarrez) votre serveur pour appliquer les changements.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	Changer la graine, le type de monde ou le nom du dossier n'affecte qu'un NOUVEAU monde. Votre monde actuel reste tel quel.
Backup saved: {0}	Sauvegarde enregistrée : {0}
Making a backup first ...	Sauvegarde préalable en cours ...
The backup failed - stopping here so nothing is lost.	La sauvegarde a échoué - arrêt ici pour ne rien perdre.
Which server do you want to change?	Quel serveur voulez-vous modifier ?
Pick another folder ...	Choisir un autre dossier ...
Type the folder of your server (the one that contains start-all):	Saisissez le dossier de votre serveur (celui qui contient start-all) :
That folder does not look like a server made by this tool.	Ce dossier ne ressemble pas à un serveur créé avec cet outil.
{0} file(s) placed in {1}	{0} fichier(s) placé(s) dans {1}
Nothing is installed in this folder yet.	Rien n'est encore installé dans ce dossier.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	Cochez ceux à RETIRER (ils sont déplacés dans un dossier nommé removed, pas supprimés)
Removed {0}	{0} retiré
Fetching version list ...	Récupération de la liste des versions ...
Could not get the version list (is the internet working?).	Impossible d'obtenir la liste des versions (Internet fonctionne-t-il ?).
That is the version you already have.	C'est la version que vous avez déjà.
Change Minecraft from {0} to {1}?	Passer Minecraft de {0} à {1} ?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	Les mondes ne peuvent pas revenir à une version plus ancienne, une sauvegarde complète est donc faite d'abord. Les plugins et mods devront peut-être être mis à jour ensuite.
Now on Minecraft {0}	Désormais sous Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	Si un plugin ou un mod cesse de fonctionner avec la nouvelle version, mettez-le à jour ou retirez-le depuis ce menu. Pour revenir en arrière, restaurez la sauvegarde du dossier backups.
This loader has no release for that version.	Ce chargeur n'a pas de version pour celle-ci.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	La prise en charge de Bedrock est ACTIVÉE. La désactiver ? (Geyser et Floodgate sont déplacés dans un dossier nommé removed.)
Bedrock support turned off.	Prise en charge de Bedrock désactivée.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	La prise en charge de Bedrock nécessite ici un serveur PaperMC simple (pas Velocity, Fabric ni Forge).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	Autoriser aussi les joueurs Bedrock (téléphones, consoles, Windows 10/11) ?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Geyser et Floodgate sont ajoutés. Ils nécessitent PaperMC. Les pseudos Bedrock ont un point devant (par exemple .Steve). Le port UDP {0} est utilisé.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	Votre serveur est Vanilla. Le passer à PaperMC (même version, même monde) ? Une sauvegarde complète est faite d'abord.
PaperMC has no build for this version.	PaperMC n'a pas de build pour cette version.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Les joueurs Bedrock ont besoin que le port UDP {0} soit accessible. Avec playit.gg, lancez  bash mc-setup.sh --tunnel-guide  pour ajouter le tunnel Bedrock ; avec une box, redirigez aussi l'UDP {0}.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Les joueurs Bedrock ont besoin que le port UDP {0} soit accessible. Avec playit.gg, lancez  powershell -File mc-setup.ps1 -TunnelGuide  pour ajouter le tunnel Bedrock ; avec une box, redirigez aussi l'UDP {0}.
In my home folder	Dans mon dossier personnel
EOF
}
lang_data_de() { cat <<'EOF'
Let's set up your Minecraft server	Richten wir deinen Minecraft-Server ein
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	Benutze die Pfeiltasten und Enter. Mit Strg+C beendest du jederzeit.
Nothing is installed until you confirm at the end.	Es wird nichts installiert, bis du am Ende bestätigst.
How do you want to set up?	Wie möchtest du einrichten?
Simple - a few easy questions, everything else is chosen for you	Einfach: ein paar leichte Fragen, der Rest wird für dich gewählt
Advanced - choose every option yourself	Erweitert: du wählst jede Option selbst
What do you want to call your server?	Wie soll dein Server heißen?
Where should your server be saved? A new folder with your server's name is created there.	Wo soll dein Server gespeichert werden? Dort wird ein neuer Ordner mit seinem Namen angelegt.
Next to this script (recommended)	Neben diesem Skript (empfohlen)
On my Desktop	Auf meinem Desktop
In my Documents folder	In meinem Dokumente-Ordner
Somewhere else (type a folder)	Anderswo (Ordner eingeben)
Somewhere else (browse or type a folder)	Anderswo (durchsuchen oder Ordner eingeben)
Your server will be installed in:	Dein Server wird installiert in:
Yes, use this folder	Ja, diesen Ordner benutzen
No, pick another place	Nein, anderen Ort wählen
Which kind of server do you want?	Welche Art von Server möchtest du?
Standard (recommended) - fast, and you can add plugins later	Standard (empfohlen): schnell, Plugins kannst du später hinzufügen
Pure Minecraft - exactly like the official game	Reines Minecraft: genau wie das Originalspiel
How will your friends join?	Wie sollen deine Freunde beitreten?
Over the internet - easiest, no router settings (free)	Über das Internet: am einfachsten, keine Router-Einstellungen (gratis)
Over the internet using my router (port forwarding)	Über das Internet per Router (Portweiterleitung)
Only people on my home Wi-Fi	Nur Personen in meinem WLAN
Does everyone who will join own Minecraft (a paid Microsoft account)?	Besitzen alle, die beitreten, Minecraft (bezahltes Microsoft-Konto)?
YES = safest, recommended.	JA = am sichersten, empfohlen.
NO  = anyone can join with any name (only for friends you trust).	NEIN = jeder kann mit beliebigem Namen beitreten (nur für vertrauenswürdige Freunde).
Yes	Ja
No	Nein
Finding the newest version ...	Suche die neueste Version ...
Want to change more things (server message, icon, mods, whitelist, world...)?	Möchtest du mehr ändern (Nachricht, Icon, Mods, Whitelist, Welt ...)?
Most people choose No - you can still do that later.	Die meisten wählen Nein – das geht auch später noch.
Minecraft EULA	Minecraft-EULA
To run a server you must agree to the Minecraft End User License Agreement:	Um einen Server zu betreiben, musst du der Minecraft-Endbenutzer-Lizenzvereinbarung zustimmen:
Do you agree to the EULA?	Stimmst du der EULA zu?
Summary	Zusammenfassung
Install now?	Jetzt installieren?
Installing your Minecraft server	Dein Minecraft-Server wird installiert
Step 1 of 4 - Checking Java	Schritt 1 von 4: Java prüfen
Step 2 of 4 - Downloading Minecraft (this can take a minute)	Schritt 2 von 4: Minecraft wird heruntergeladen (kann eine Minute dauern)
Step 3 of 4 - Setting up internet access	Schritt 3 von 4: Internetzugang einrichten
Step 4 of 4 - Finishing up	Schritt 4 von 4: Abschluss
Your server is ready	Dein Server ist bereit
To start your server, run:	Um deinen Server zu starten, führe aus:
To stop it, type  stop  in the server window.	Zum Beenden gib  stop  im Serverfenster ein.
Friends join with:	Freunde treten bei mit:
Note: anyone can join with any name. Only share the address with people you trust.	Hinweis: Jeder kann mit beliebigem Namen beitreten. Gib die Adresse nur an vertrauenswürdige Leute weiter.
(Your playit.gg address. Keep playit running while you play.)	(Deine playit.gg-Adresse. Lass playit beim Spielen laufen.)
(Only on the same Wi-Fi.)	(Nur im selben WLAN.)
Start the server now?	Server jetzt starten?
All set - have fun!	Alles fertig – viel Spaß!
Setup cancelled. Nothing was installed.	Einrichtung abgebrochen. Es wurde nichts installiert.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	Jetzt deinen kostenlosen playit.gg-Tunnel mit einer Schritt-für-Schritt-Anleitung einrichten? (ca. 10 Minuten, geht auch später)
playit.gg tunnel	playit.gg-Tunnel
Name:	Name:
Type:	Typ:
Friends:	Freunde:
Accounts:	Konten:
Memory:	Speicher:
Folder:	Ordner:
Standard	Standard
Pure Minecraft	Reines Minecraft
over the internet (free tunnel)	über das Internet (kostenloser Tunnel)
over the internet (router port forwarding)	über das Internet (Portweiterleitung)
home Wi-Fi only	nur Heim-WLAN
everyone needs a Minecraft account	alle brauchen ein Minecraft-Konto
anyone can join with any name	jeder kann mit beliebigem Namen beitreten
Press Enter to close	Zum Schließen Enter drücken
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	Ich bin nicht sicher, ob dieses Fenster diese Sprache anzeigen kann. Wenn du nach der Auswahl Kästchen oder ? siehst, starte neu und wähle Englisch (Windows Terminal aus dem Microsoft Store funktioniert am besten).
Use this language	Diese Sprache verwenden
Use English instead	Stattdessen Englisch verwenden
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	Dieses Terminal ist nicht auf UTF-8 eingestellt, daher kann diese Sprache fehlerhaft aussehen (Kästchen oder ?). Auf Englisch fortfahren?
Use English	Englisch verwenden
Try it anyway	Trotzdem versuchen
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	Tipp: Wenn du Kästchen statt Buchstaben siehst, starte erneut mit  -Lang en  oder nutze Windows Terminal.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	Tipp: Wenn du Kästchen statt Buchstaben siehst, starte erneut mit  --lang en  oder nutze ein Terminal mit passender Schrift.
none	keins
plugins	Plugins
mods	Mods
Back	Zurück
Customise your server. Pick a category; choose 'done' when finished.	Passe deinen Server an. Wähle eine Kategorie; wähle am Ende „fertig“.
Server name: {0}	Servername: {0}
Server list message with colours: {0}	Servernachricht mit Farben: {0}
Server icon: {0}	Server-Symbol: {0}
Mods: {0} queued	Mods: {0} vorgemerkt
Plugins: {0} queued	Plugins: {0} vorgemerkt
Operators ({0}) and whitelist ({1})	Operatoren ({0}) und Whitelist ({1})
World type, seed, structures, nether, hardcore	Welttyp, Seed, Strukturen, Nether, Hardcore
PvP, command blocks, flying, mobs, spawn protection	PvP, Befehlsblöcke, Fliegen, Mobs, Spawn-Schutz
View / simulation distance: {0} / {1}	Sicht- / Simulationsdistanz: {0} / {1}
Resource pack: {0}	Ressourcenpaket: {0}
Any other server.properties setting ({0})	Beliebige andere server.properties-Einstellung ({0})
Auto-restart on crash, backup script	Auto-Neustart bei Absturz, Backup-Skript
Finished customising	Anpassung beenden
Name of your server (e.g. Creeper Cove).	Name deines Servers (z. B. Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	Wird für Fenstertitel, den Autostart-Eintrag, Backups und – falls du keine eigene Nachricht festlegst – als Nachricht in der Serverliste verwendet.
Server list message (MOTD).	Nachricht in der Serverliste (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	Farben: &0 schwarz &1 dunkelblau &2 dunkelgrün &3 dunkelaqua &4 dunkelrot &5 lila &6 gold
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 grau &8 dunkelgrau &9 blau &a grün &b aqua &c rot &d rosa &e gelb &f weiß
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	Stile:  &l fett  &o kursiv  &n unterstrichen  &k verwürfelt  &r zurücksetzen
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	Mit \n beginnst du eine zweite Zeile.    Beispiel: &6&lMein Server\n&7Willkommen!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	Server-Symbol: Pfad zu einem Bild (png/jpg/gif...) oder ein https://-Link.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	Wird automatisch auf 64x64 Pixel umgewandelt (mittig quadratisch zugeschnitten).
Leave empty for no icon.	Leer lassen für kein Symbol.
File not found: {0}	Datei nicht gefunden: {0}
Server icon created (64x64)	Server-Symbol erstellt (64x64)
Checking which popular {0} work with Minecraft {1} ...	Prüfe, welche beliebten {0} mit Minecraft {1} funktionieren ...
[not updated for {0} yet - newest version will be tried]	[noch nicht für {0} aktualisiert – die neueste Version wird versucht]
You already added everything in the popular list. Try the search option for more.	Du hast schon alles aus der Liste hinzugefügt. Nutze die Suche für mehr.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} ist sehr neu, daher sind {1} Plugin(s) als noch nicht aktualisiert markiert. Oft funktionieren sie trotzdem; wähle sie aus, wenn du es versuchen willst.
Pick the {0} you want (Space = tick, Enter = done, A = all)	Wähle die gewünschten {0} (Leertaste = anhaken, Enter = fertig, A = alle)
Added {0}	{0} hinzugefügt
Add {0}  ({1} queued, loader: {2})	{0} hinzufügen  ({1} vorgemerkt, Loader: {2})
Add {0}  ({1} queued)	{0} hinzufügen  ({1} vorgemerkt)
Pick from a list of popular {0}	Aus einer Liste beliebter {0} wählen
Search Modrinth for {0} (compatible with {1})	Auf Modrinth nach {0} suchen (kompatibel mit {1})
Add direct https:// links to .jar files	Direkte https://-Links zu .jar-Dateien hinzufügen
Show / remove queued {0}	Vorgemerkte {0} anzeigen / entfernen
Done with {0}	{0} fertig
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Auf Modrinth suchen ({0} für Minecraft {1}). Beispiele: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	Die Modrinth-Suche ist fehlgeschlagen.
Nothing found for '{0}' that works with Minecraft {1}.	Nichts zu „{0}“ gefunden, das mit Minecraft {1} funktioniert.
Results for '{0}':	Ergebnisse für „{0}“:
Added '{0}' (and any required dependencies).	„{0}“ hinzugefügt (und alle nötigen Abhängigkeiten).
Direct https:// links to .jar files, separated by spaces.	Direkte https://-Links zu .jar-Dateien, durch Leerzeichen getrennt.
Only use links from sources you trust - these files run on your server.	Nutze nur Links aus vertrauenswürdigen Quellen – diese Dateien laufen auf deinem Server.
Skipping '{0}' (must start with https://)	„{0}“ übersprungen (muss mit https:// beginnen)
Nothing queued yet.	Noch nichts vorgemerkt.
Back (keep everything)	Zurück (alles behalten)
Pick one to REMOVE from the install list:	Wähle einen zum ENTFERNEN aus der Installationsliste:
Skipping invalid name '{0}'	Ungültiger Name „{0}“ übersprungen
Operators (admins). Minecraft usernames separated by spaces or commas.	Operatoren (Admins). Minecraft-Benutzernamen, durch Leerzeichen oder Kommas getrennt.
Ops can use all commands.	Operatoren dürfen alle Befehle nutzen.
Whitelist: only these players may join. Usernames separated by spaces or commas.	Whitelist: Nur diese Spieler dürfen beitreten. Benutzernamen durch Leerzeichen oder Kommas getrennt.
Leave empty to keep the whitelist as chosen earlier.	Leer lassen, um die zuvor gewählte Whitelist zu behalten.
Could not look up '{0}' - add later with: whitelist add {0}	„{0}“ konnte nicht gefunden werden – später hinzufügen mit: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	„{0}“ konnte nicht gefunden werden – später hinzufügen mit: op {0}
World type:	Welttyp:
Normal terrain	Normales Gelände
Superflat	Superflach
Large biomes	Große Biome
Amplified (tall mountains)	Amplified (hohe Berge)
World seed (empty = random):	Welt-Seed (leer = zufällig):
World folder name:	Name des Weltordners:
Generate structures (villages, strongholds, ...)?	Strukturen generieren (Dörfer, Festungen, ...)?
Allow the Nether?	Nether erlauben?
Hardcore mode? (one life, forced hard difficulty)	Hardcore-Modus? (ein Leben, erzwungen schwer)
Allow player-vs-player combat (PvP)?	Kämpfe zwischen Spielern (PvP) erlauben?
Enable command blocks?	Befehlsblöcke aktivieren?
Allow flying (needed for some mods; otherwise flight is kicked)?	Fliegen erlauben (für manche Mods nötig; sonst wird Fliegen mit Kick bestraft)?
Spawn animals?	Tiere spawnen?
Spawn monsters?	Monster spawnen?
Spawn villagers?	Dorfbewohner spawnen?
Force everyone into the default game mode on every join?	Alle bei jedem Beitritt in den Standard-Spielmodus zwingen?
Spawn protection radius in blocks (0 = off):	Spawn-Schutzradius in Blöcken (0 = aus):
Kick idle players after N minutes (0 = never):	Inaktive Spieler nach N Minuten kicken (0 = nie):
View distance in chunks (2-32). Lower = faster:	Sichtweite in Chunks (2-32). Niedriger = schneller:
Simulation distance in chunks (2-32). Lower = faster:	Simulationsdistanz in Chunks (2-32). Niedriger = schneller:
Please enter a number from {0} to {1}. Kept: {2}	Bitte eine Zahl von {0} bis {1} eingeben. Beibehalten: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	Server-Ressourcenpaket: direkter https://-Link zu einer .zip (leer = keins).
Players are offered it when they join. Its checksum is calculated at install time.	Spielern wird es beim Beitritt angeboten. Die Prüfsumme wird bei der Installation berechnet.
That is not a link. Kept: {0}	Das ist kein Link. Beibehalten: {0}
Kick players who decline the resource pack?	Spieler kicken, die das Ressourcenpaket ablehnen?
Any other server.properties setting as key=value, separated by spaces.	Beliebige andere server.properties-Einstellung als Schlüssel=Wert, durch Leerzeichen getrennt.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	Beispiel: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	„{0}“ übersprungen (Schlüssel=Wert verwenden)
Restart the server automatically if it crashes?	Server bei einem Absturz automatisch neu starten?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	Backup-Skript erstellen (packt die Welt in den Ordner backups, behält die neuesten 10)?
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	Mod-Loader lassen sich hier nicht mit dem Velocity-Setup kombinieren. (Paper-Plugins schon – wähle PaperMC.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla unterstützt selbst keine Mods. Wähle einen Mod-Loader (er ersetzt den normalen Vanilla-Server):
Fabric - lightweight, huge mod library (recommended)	Fabric – leichtgewichtig, riesige Mod-Auswahl (empfohlen)
NeoForge - big content mods (1.20.2+)	NeoForge – große Inhalts-Mods (1.20.2+)
Forge - classic loader (1.17+)	Forge – klassischer Loader (1.17+)
Plain Vanilla, no mods	Reines Vanilla, keine Mods
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} hat keine Server-Version für Minecraft {1}. Wähle einen anderen Loader oder eine andere Minecraft-Version.
Modrinth lookup failed for '{0}'.	Modrinth-Abfrage für „{0}“ fehlgeschlagen.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	„{0}“ ist noch nicht für {1} markiert – die neueste Version ({2}) wurde hinzugefügt. Sie funktioniert vielleicht trotzdem.
'{0}' has no download for {1} on this loader.	„{0}“ hat keinen Download für {1} mit diesem Loader.
Newest (recommended)	Neueste (empfohlen)
Type a specific older version	Eine bestimmte ältere Version eingeben
Which Minecraft version? (newest first)	Welche Minecraft-Version? (neueste zuerst)
Type the exact Minecraft version (e.g. 1.20.1):	Gib die genaue Minecraft-Version ein (z. B. 1.20.1):
That version is not available. Pick one from the list instead.	Diese Version ist nicht verfügbar. Wähle stattdessen eine aus der Liste.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	Sollen auch Bedrock-Spieler (Handy, Konsole, Windows 10/11) beitreten können?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	Sie treten über ein kostenloses Add-on namens Geyser bei und brauchen daher kein Java-Konto. Dafür ist der Standard-Server (Paper) nötig, der für dich gewählt wird. Bedrock-Namen bekommen einen Punkt davor (z. B. .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	Auch Bedrock-Spielern den Beitritt erlauben (Geyser + Floodgate)?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Spieler der Bedrock Edition (Handy, Konsole, Windows 10/11) können dann ohne Java-Konto beitreten. Nötig ist PaperMC; der UDP-Port 19132 wird geöffnet. Bedrock-Namen bekommen einen Punkt davor (z. B. .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Auf den Standard-Server (PaperMC) umgestellt, weil die Bedrock-Unterstützung ihn braucht.
Downloading Geyser and Floodgate (Bedrock support) ...	Lade Geyser und Floodgate herunter (Bedrock-Unterstützung) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Bedrock-Unterstützung installiert (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	auch Handys, Konsolen und Windows 10/11 können beitreten
Bedrock players (phones, consoles, Windows 10/11) join with:	Bedrock-Spieler (Handy, Konsole, Windows 10/11) treten bei mit:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(In Minecraft Bedrock: Spielen > Server > Server hinzufügen. Ihre Namen bekommen einen Punkt davor, z. B. .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	Tipp: Stoppe zuerst den Server (tippe  stop  in seinem Fenster). Änderungen werden beim Start gelesen.
What do you want to change?	Was möchtest du ändern?
Server icon	Server-Symbol
Add plugins	Plugins hinzufügen
Add mods	Mods hinzufügen
Remove plugins	Plugins entfernen
Remove mods	Mods entfernen
Any other server.properties setting	Beliebige andere server.properties-Einstellung
Change the Minecraft version (now {0})	Minecraft-Version ändern (jetzt {0})
Bedrock players: ON (Geyser + Floodgate)	Bedrock-Spieler: AN (Geyser + Floodgate)
Bedrock players: off	Bedrock-Spieler: aus
Make a backup now	Jetzt ein Backup erstellen
Saved.	Gespeichert.
All done. Start (or restart) your server to use the changes.	Fertig. Starte (oder starte neu) deinen Server, um die Änderungen zu nutzen.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	Seed, Welttyp oder Weltordnername zu ändern betrifft nur eine NEUE Welt. Deine aktuelle Welt bleibt unverändert.
Backup saved: {0}	Backup gespeichert: {0}
Making a backup first ...	Erstelle zuerst ein Backup ...
The backup failed - stopping here so nothing is lost.	Das Backup ist fehlgeschlagen – ich halte hier an, damit nichts verloren geht.
Which server do you want to change?	Welchen Server möchtest du ändern?
Pick another folder ...	Anderen Ordner wählen ...
Type the folder of your server (the one that contains start-all):	Gib den Ordner deines Servers ein (der mit start-all):
That folder does not look like a server made by this tool.	Dieser Ordner sieht nicht wie ein mit diesem Tool erstellter Server aus.
{0} file(s) placed in {1}	{0} Datei(en) in {1} abgelegt
Nothing is installed in this folder yet.	In diesem Ordner ist noch nichts installiert.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	Hake die zum ENTFERNEN an (sie werden in einen Ordner namens removed verschoben, nicht gelöscht)
Removed {0}	{0} entfernt
Fetching version list ...	Lade die Versionsliste ...
Could not get the version list (is the internet working?).	Die Versionsliste konnte nicht geladen werden (funktioniert das Internet?).
That is the version you already have.	Das ist die Version, die du bereits hast.
Change Minecraft from {0} to {1}?	Minecraft von {0} auf {1} ändern?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	Welten können nicht zu einer älteren Version zurück, daher wird zuerst ein vollständiges Backup erstellt. Plugins und Mods müssen danach eventuell aktualisiert werden.
Now on Minecraft {0}	Jetzt auf Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	Wenn ein Plugin oder Mod mit der neuen Version nicht mehr läuft, aktualisiere oder entferne es über dieses Menü. Zum Zurückgehen stelle das Backup aus dem Ordner backups wieder her.
This loader has no release for that version.	Dieser Loader hat keine Version dafür.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	Die Bedrock-Unterstützung ist AN. Ausschalten? (Geyser und Floodgate werden in einen Ordner namens removed verschoben.)
Bedrock support turned off.	Bedrock-Unterstützung ausgeschaltet.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	Die Bedrock-Unterstützung braucht hier einen normalen PaperMC-Server (nicht Velocity, Fabric oder Forge).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	Auch Bedrock-Spielern (Handy, Konsole, Windows 10/11) den Beitritt erlauben?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Geyser und Floodgate werden hinzugefügt. Sie brauchen PaperMC. Bedrock-Namen bekommen einen Punkt davor (z. B. .Steve). Es wird der UDP-Port {0} verwendet.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	Dein Server ist Vanilla. Auf PaperMC umstellen (gleiche Version, gleiche Welt)? Vorher wird ein vollständiges Backup erstellt.
PaperMC has no build for this version.	PaperMC hat keinen Build für diese Version.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock-Spieler brauchen einen erreichbaren UDP-Port {0}. Mit playit.gg führe  bash mc-setup.sh --tunnel-guide  aus, um den Bedrock-Tunnel hinzuzufügen; beim Router leite auch UDP {0} weiter.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock-Spieler brauchen einen erreichbaren UDP-Port {0}. Mit playit.gg führe  powershell -File mc-setup.ps1 -TunnelGuide  aus, um den Bedrock-Tunnel hinzuzufügen; beim Router leite auch UDP {0} weiter.
In my home folder	In meinem Home-Ordner
EOF
}
lang_data_pt() { cat <<'EOF'
Let's set up your Minecraft server	Vamos configurar o seu servidor de Minecraft
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	Use as setas e Enter. Pressione Ctrl+C a qualquer momento para sair.
Nothing is installed until you confirm at the end.	Nada é instalado até você confirmar no final.
How do you want to set up?	Como você quer configurar?
Simple - a few easy questions, everything else is chosen for you	Simples: poucas perguntas fáceis, o resto é escolhido por você
Advanced - choose every option yourself	Avançado: escolha todas as opções você mesmo
What do you want to call your server?	Como você quer chamar o seu servidor?
Where should your server be saved? A new folder with your server's name is created there.	Onde salvar o seu servidor? Uma nova pasta com o nome dele será criada lá.
Next to this script (recommended)	Ao lado deste script (recomendado)
On my Desktop	Na minha Área de Trabalho
In my Documents folder	Na minha pasta Documentos
Somewhere else (type a folder)	Outro lugar (digite uma pasta)
Somewhere else (browse or type a folder)	Outro lugar (procurar ou digitar uma pasta)
Your server will be installed in:	Seu servidor será instalado em:
Yes, use this folder	Sim, usar esta pasta
No, pick another place	Não, escolher outro lugar
Which kind of server do you want?	Que tipo de servidor você quer?
Standard (recommended) - fast, and you can add plugins later	Padrão (recomendado): rápido, e você pode adicionar plugins depois
Pure Minecraft - exactly like the official game	Minecraft puro: exatamente como o jogo oficial
How will your friends join?	Como seus amigos vão entrar?
Over the internet - easiest, no router settings (free)	Pela internet: o mais fácil, sem mexer no roteador (grátis)
Over the internet using my router (port forwarding)	Pela internet usando meu roteador (redirecionamento de portas)
Only people on my home Wi-Fi	Apenas pessoas no meu Wi-Fi de casa
Does everyone who will join own Minecraft (a paid Microsoft account)?	Todos que vão entrar têm Minecraft (conta Microsoft paga)?
YES = safest, recommended.	SIM = o mais seguro, recomendado.
NO  = anyone can join with any name (only for friends you trust).	NÃO = qualquer pessoa entra com qualquer nome (só para amigos de confiança).
Yes	Sim
No	Não
Finding the newest version ...	Procurando a versão mais recente ...
Want to change more things (server message, icon, mods, whitelist, world...)?	Quer mudar mais coisas (mensagem, ícone, mods, whitelist, mundo...)?
Most people choose No - you can still do that later.	A maioria escolhe Não; você pode fazer isso depois.
Minecraft EULA	EULA do Minecraft
To run a server you must agree to the Minecraft End User License Agreement:	Para executar um servidor, você deve aceitar o Contrato de Licença de Usuário Final do Minecraft:
Do you agree to the EULA?	Você aceita o EULA?
Summary	Resumo
Install now?	Instalar agora?
Installing your Minecraft server	Instalando o seu servidor de Minecraft
Step 1 of 4 - Checking Java	Passo 1 de 4: verificando o Java
Step 2 of 4 - Downloading Minecraft (this can take a minute)	Passo 2 de 4: baixando o Minecraft (pode levar um minuto)
Step 3 of 4 - Setting up internet access	Passo 3 de 4: configurando o acesso à internet
Step 4 of 4 - Finishing up	Passo 4 de 4: finalizando
Your server is ready	Seu servidor está pronto
To start your server, run:	Para iniciar o seu servidor, execute:
To stop it, type  stop  in the server window.	Para parar, digite  stop  na janela do servidor.
Friends join with:	Seus amigos entram com:
Note: anyone can join with any name. Only share the address with people you trust.	Nota: qualquer pessoa entra com qualquer nome. Compartilhe o endereço só com quem você confia.
(Your playit.gg address. Keep playit running while you play.)	(Seu endereço do playit.gg. Mantenha o playit aberto enquanto joga.)
(Only on the same Wi-Fi.)	(Somente no mesmo Wi-Fi.)
Start the server now?	Iniciar o servidor agora?
All set - have fun!	Tudo pronto, divirta-se!
Setup cancelled. Nothing was installed.	Configuração cancelada. Nada foi instalado.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	Configurar agora seu túnel gratuito do playit.gg com um guia passo a passo? (cerca de 10 minutos; dá para fazer depois)
playit.gg tunnel	Túnel playit.gg
Name:	Nome:
Type:	Tipo:
Friends:	Amigos:
Accounts:	Contas:
Memory:	Memória:
Folder:	Pasta:
Standard	Padrão
Pure Minecraft	Minecraft puro
over the internet (free tunnel)	pela internet (túnel gratuito)
over the internet (router port forwarding)	pela internet (redirecionamento de portas)
home Wi-Fi only	somente Wi-Fi de casa
everyone needs a Minecraft account	todos precisam de uma conta do Minecraft
anyone can join with any name	qualquer pessoa entra com qualquer nome
Press Enter to close	Pressione Enter para fechar
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	Não tenho certeza se esta janela consegue mostrar este idioma. Se você vir quadrados ou ? depois de escolher, reinicie e escolha inglês (o Windows Terminal da Microsoft Store funciona melhor).
Use this language	Usar este idioma
Use English instead	Usar inglês em vez disso
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	Este terminal não está em UTF-8, então este idioma pode aparecer quebrado (quadrados ou ?). Continuar em inglês?
Use English	Usar inglês
Try it anyway	Tentar mesmo assim
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	Dica: se você vir quadrados em vez de letras, execute de novo com  -Lang en  ou use o Windows Terminal.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	Dica: se você vir quadrados em vez de letras, execute de novo com  --lang en  ou use um terminal com fonte compatível.
none	nenhum
plugins	plugins
mods	mods
Back	Voltar
Customise your server. Pick a category; choose 'done' when finished.	Personalize seu servidor. Escolha uma categoria; escolha «concluído» ao terminar.
Server name: {0}	Nome do servidor: {0}
Server list message with colours: {0}	Mensagem da lista de servidores com cores: {0}
Server icon: {0}	Ícone do servidor: {0}
Mods: {0} queued	Mods: {0} na fila
Plugins: {0} queued	Plugins: {0} na fila
Operators ({0}) and whitelist ({1})	Operadores ({0}) e lista de permissões ({1})
World type, seed, structures, nether, hardcore	Tipo de mundo, semente, estruturas, Nether, hardcore
PvP, command blocks, flying, mobs, spawn protection	PvP, blocos de comando, voo, mobs, proteção do spawn
View / simulation distance: {0} / {1}	Distância de visão / simulação: {0} / {1}
Resource pack: {0}	Pacote de recursos: {0}
Any other server.properties setting ({0})	Qualquer outra configuração do server.properties ({0})
Auto-restart on crash, backup script	Reinício automático em caso de falha, script de backup
Finished customising	Concluir personalização
Name of your server (e.g. Creeper Cove).	Nome do seu servidor (ex.: Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	Usado nos títulos de janela, na inicialização automática, nos backups e, se você não definir outra, como mensagem na lista de servidores.
Server list message (MOTD).	Mensagem da lista de servidores (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	Cores: &0 preto &1 azul-escuro &2 verde-escuro &3 ciano-escuro &4 vermelho-escuro &5 roxo &6 dourado
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 cinza &8 cinza-escuro &9 azul &a verde &b ciano &c vermelho &d rosa &e amarelo &f branco
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	Estilos:  &l negrito  &o itálico  &n sublinhado  &k embaralhado  &r redefinir
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	Use \n para uma segunda linha.    Exemplo: &6&lMeu Servidor\n&7Bem-vindo!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	Ícone do servidor: caminho de uma imagem (png/jpg/gif...) ou link https://.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	É convertido automaticamente para 64x64 pixels (cortado ao centro em quadrado).
Leave empty for no icon.	Deixe vazio para não usar ícone.
File not found: {0}	Arquivo não encontrado: {0}
Server icon created (64x64)	Ícone do servidor criado (64x64)
Checking which popular {0} work with Minecraft {1} ...	Verificando quais {0} populares funcionam com o Minecraft {1} ...
[not updated for {0} yet - newest version will be tried]	[ainda não atualizado para {0} - a versão mais recente será tentada]
You already added everything in the popular list. Try the search option for more.	Você já adicionou tudo da lista popular. Tente a busca para ver mais.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	O Minecraft {0} é muito novo, então {1} plugin(s) estão marcados como não atualizados. Muitas vezes ainda funcionam; escolha-os se quiser tentar.
Pick the {0} you want (Space = tick, Enter = done, A = all)	Escolha os {0} que quiser (Espaço = marcar, Enter = concluir, A = todos)
Added {0}	{0} adicionado
Add {0}  ({1} queued, loader: {2})	Adicionar {0}  ({1} na fila, loader: {2})
Add {0}  ({1} queued)	Adicionar {0}  ({1} na fila)
Pick from a list of popular {0}	Escolher de uma lista de {0} populares
Search Modrinth for {0} (compatible with {1})	Buscar {0} no Modrinth (compatíveis com {1})
Add direct https:// links to .jar files	Adicionar links https:// diretos para arquivos .jar
Show / remove queued {0}	Ver / remover {0} na fila
Done with {0}	Concluir {0}
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Buscar no Modrinth ({0} para Minecraft {1}). Exemplos: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	A busca no Modrinth falhou.
Nothing found for '{0}' that works with Minecraft {1}.	Nada encontrado para '{0}' que funcione com o Minecraft {1}.
Results for '{0}':	Resultados para '{0}':
Added '{0}' (and any required dependencies).	'{0}' adicionado (e as dependências necessárias).
Direct https:// links to .jar files, separated by spaces.	Links https:// diretos para arquivos .jar, separados por espaços.
Only use links from sources you trust - these files run on your server.	Use apenas links de fontes confiáveis - esses arquivos rodam no seu servidor.
Skipping '{0}' (must start with https://)	'{0}' ignorado (deve começar com https://)
Nothing queued yet.	Nada na fila ainda.
Back (keep everything)	Voltar (manter tudo)
Pick one to REMOVE from the install list:	Escolha um para REMOVER da lista de instalação:
Skipping invalid name '{0}'	Nome inválido '{0}' ignorado
Operators (admins). Minecraft usernames separated by spaces or commas.	Operadores (administradores). Nomes de usuário do Minecraft separados por espaços ou vírgulas.
Ops can use all commands.	Operadores podem usar todos os comandos.
Whitelist: only these players may join. Usernames separated by spaces or commas.	Lista de permissões: só estes jogadores podem entrar. Nomes separados por espaços ou vírgulas.
Leave empty to keep the whitelist as chosen earlier.	Deixe vazio para manter a lista de permissões escolhida antes.
Could not look up '{0}' - add later with: whitelist add {0}	Não foi possível consultar '{0}' - adicione depois com: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	Não foi possível consultar '{0}' - adicione depois com: op {0}
World type:	Tipo de mundo:
Normal terrain	Terreno normal
Superflat	Superplano
Large biomes	Biomas grandes
Amplified (tall mountains)	Amplificado (montanhas altas)
World seed (empty = random):	Semente do mundo (vazio = aleatória):
World folder name:	Nome da pasta do mundo:
Generate structures (villages, strongholds, ...)?	Gerar estruturas (vilas, fortalezas, ...)?
Allow the Nether?	Permitir o Nether?
Hardcore mode? (one life, forced hard difficulty)	Modo hardcore? (uma vida, dificuldade difícil forçada)
Allow player-vs-player combat (PvP)?	Permitir combate entre jogadores (PvP)?
Enable command blocks?	Ativar blocos de comando?
Allow flying (needed for some mods; otherwise flight is kicked)?	Permitir voar (necessário para alguns mods; senão o voo causa expulsão)?
Spawn animals?	Gerar animais?
Spawn monsters?	Gerar monstros?
Spawn villagers?	Gerar aldeões?
Force everyone into the default game mode on every join?	Forçar todos ao modo de jogo padrão a cada entrada?
Spawn protection radius in blocks (0 = off):	Raio de proteção do spawn em blocos (0 = desligado):
Kick idle players after N minutes (0 = never):	Expulsar jogadores inativos após N minutos (0 = nunca):
View distance in chunks (2-32). Lower = faster:	Distância de visão em chunks (2-32). Menor = mais rápido:
Simulation distance in chunks (2-32). Lower = faster:	Distância de simulação em chunks (2-32). Menor = mais rápido:
Please enter a number from {0} to {1}. Kept: {2}	Digite um número de {0} a {1}. Mantido: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	Pacote de recursos do servidor: link https:// direto para um .zip (vazio = nenhum).
Players are offered it when they join. Its checksum is calculated at install time.	É oferecido aos jogadores ao entrarem. A soma de verificação é calculada na instalação.
That is not a link. Kept: {0}	Isso não é um link. Mantido: {0}
Kick players who decline the resource pack?	Expulsar jogadores que recusarem o pacote de recursos?
Any other server.properties setting as key=value, separated by spaces.	Qualquer outra configuração do server.properties como chave=valor, separadas por espaços.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	Exemplo: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	'{0}' ignorado (use chave=valor)
Restart the server automatically if it crashes?	Reiniciar o servidor automaticamente se ele travar?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	Criar um script de backup (compacta o mundo na pasta backups, mantém as 10 mais recentes)?
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	Carregadores de mods não podem ser combinados aqui com a configuração Velocity. (Plugins do Paper podem - escolha PaperMC.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	O Vanilla não suporta mods por si só. Escolha um carregador de mods (ele substitui o servidor Vanilla simples):
Fabric - lightweight, huge mod library (recommended)	Fabric - leve, enorme biblioteca de mods (recomendado)
NeoForge - big content mods (1.20.2+)	NeoForge - mods de conteúdo grandes (1.20.2+)
Forge - classic loader (1.17+)	Forge - carregador clássico (1.17+)
Plain Vanilla, no mods	Vanilla puro, sem mods
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} não tem versão de servidor para o Minecraft {1}. Escolha outro carregador ou outra versão do Minecraft.
Modrinth lookup failed for '{0}'.	A consulta de '{0}' no Modrinth falhou.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	'{0}' ainda não está marcado para {1} - a versão mais recente ({2}) foi adicionada. Ainda pode funcionar.
'{0}' has no download for {1} on this loader.	'{0}' não tem download para {1} neste carregador.
Newest (recommended)	Mais recente (recomendada)
Type a specific older version	Digitar uma versão mais antiga específica
Which Minecraft version? (newest first)	Qual versão do Minecraft? (a mais recente primeiro)
Type the exact Minecraft version (e.g. 1.20.1):	Digite a versão exata do Minecraft (ex.: 1.20.1):
That version is not available. Pick one from the list instead.	Essa versão não está disponível. Escolha uma da lista.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	Jogadores do Bedrock (celulares, consoles, Windows 10/11) também devem poder entrar?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	Eles entram por um complemento gratuito chamado Geyser, então não precisam de conta Java. Precisa do servidor Padrão (Paper), que é escolhido para você. Nomes do Bedrock ganham um ponto na frente (por exemplo .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	Permitir também que jogadores do Bedrock entrem (Geyser + Floodgate)?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Jogadores do Bedrock Edition (celulares, consoles, Windows 10/11) poderão entrar sem conta Java. Precisa do PaperMC e abre a porta UDP 19132. Nomes do Bedrock ganham um ponto na frente (por exemplo .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Mudado para o servidor Padrão (PaperMC), porque o suporte ao Bedrock precisa dele.
Downloading Geyser and Floodgate (Bedrock support) ...	Baixando Geyser e Floodgate (suporte ao Bedrock) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Suporte ao Bedrock instalado (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	celulares, consoles e Windows 10/11 também podem entrar
Bedrock players (phones, consoles, Windows 10/11) join with:	Jogadores do Bedrock (celulares, consoles, Windows 10/11) entram com:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(No Minecraft Bedrock: Jogar > Servidores > Adicionar servidor. Os nomes ganham um ponto na frente, como .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	Dica: pare o servidor primeiro (digite  stop  na janela dele). As mudanças são lidas ao iniciar.
What do you want to change?	O que você quer mudar?
Server icon	Ícone do servidor
Add plugins	Adicionar plugins
Add mods	Adicionar mods
Remove plugins	Remover plugins
Remove mods	Remover mods
Any other server.properties setting	Qualquer outra configuração do server.properties
Change the Minecraft version (now {0})	Mudar a versão do Minecraft (agora {0})
Bedrock players: ON (Geyser + Floodgate)	Jogadores do Bedrock: SIM (Geyser + Floodgate)
Bedrock players: off	Jogadores do Bedrock: não
Make a backup now	Fazer um backup agora
Saved.	Salvo.
All done. Start (or restart) your server to use the changes.	Pronto. Inicie (ou reinicie) seu servidor para usar as mudanças.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	Mudar a semente, o tipo de mundo ou o nome da pasta afeta apenas um mundo NOVO. Seu mundo atual continua como está.
Backup saved: {0}	Backup salvo: {0}
Making a backup first ...	Fazendo um backup primeiro ...
The backup failed - stopping here so nothing is lost.	O backup falhou - paro aqui para não perder nada.
Which server do you want to change?	Qual servidor você quer mudar?
Pick another folder ...	Escolher outra pasta ...
Type the folder of your server (the one that contains start-all):	Digite a pasta do seu servidor (a que contém start-all):
That folder does not look like a server made by this tool.	Essa pasta não parece um servidor criado por esta ferramenta.
{0} file(s) placed in {1}	{0} arquivo(s) colocado(s) em {1}
Nothing is installed in this folder yet.	Ainda não há nada instalado nesta pasta.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	Marque os que quer REMOVER (eles vão para uma pasta chamada removed, não são apagados)
Removed {0}	{0} removido
Fetching version list ...	Buscando a lista de versões ...
Could not get the version list (is the internet working?).	Não foi possível obter a lista de versões (a internet está funcionando?).
That is the version you already have.	Essa é a versão que você já tem.
Change Minecraft from {0} to {1}?	Mudar o Minecraft de {0} para {1}?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	Mundos não podem voltar a uma versão mais antiga, então um backup completo é feito antes. Depois, plugins e mods podem precisar de atualização.
Now on Minecraft {0}	Agora no Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	Se um plugin ou mod parar de funcionar com a nova versão, atualize ou remova-o neste menu. Para voltar, restaure o backup da pasta backups.
This loader has no release for that version.	Este carregador não tem versão para essa versão.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	O suporte ao Bedrock está LIGADO. Desligar? (Geyser e Floodgate vão para uma pasta chamada removed.)
Bedrock support turned off.	Suporte ao Bedrock desligado.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	O suporte ao Bedrock aqui precisa de um servidor PaperMC simples (não Velocity, Fabric ou Forge).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	Permitir que jogadores do Bedrock (celulares, consoles, Windows 10/11) também entrem?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Geyser e Floodgate são adicionados. Eles precisam do PaperMC. Nomes do Bedrock ganham um ponto na frente (por exemplo .Steve). A porta UDP {0} é usada.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	Seu servidor é Vanilla. Mudar para PaperMC (mesma versão, mesmo mundo)? Um backup completo é feito antes.
PaperMC has no build for this version.	O PaperMC não tem build para esta versão.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Jogadores do Bedrock precisam que a porta UDP {0} esteja acessível. Com o playit.gg, rode  bash mc-setup.sh --tunnel-guide  para adicionar o túnel do Bedrock; com roteador, encaminhe também a UDP {0}.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Jogadores do Bedrock precisam que a porta UDP {0} esteja acessível. Com o playit.gg, rode  powershell -File mc-setup.ps1 -TunnelGuide  para adicionar o túnel do Bedrock; com roteador, encaminhe também a UDP {0}.
In my home folder	Na minha pasta pessoal
EOF
}
lang_data_ru() { cat <<'EOF'
Let's set up your Minecraft server	Давай настроим твой сервер Minecraft
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	Используй стрелки и Enter. Ctrl+C — выход в любой момент.
Nothing is installed until you confirm at the end.	Ничего не устанавливается, пока ты не подтвердишь в конце.
How do you want to set up?	Как будем настраивать?
Simple - a few easy questions, everything else is chosen for you	Простой: несколько вопросов, остальное выберем за тебя
Advanced - choose every option yourself	Расширенный: выбираешь все параметры сам
What do you want to call your server?	Как назовём твой сервер?
Where should your server be saved? A new folder with your server's name is created there.	Где сохранить сервер? Там будет создана новая папка с его именем.
Next to this script (recommended)	Рядом с этим скриптом (рекомендуется)
On my Desktop	На рабочем столе
In my Documents folder	В папке «Документы»
Somewhere else (type a folder)	В другом месте (введи папку)
Somewhere else (browse or type a folder)	В другом месте (обзор или ввод папки)
Your server will be installed in:	Сервер будет установлен в:
Yes, use this folder	Да, использовать эту папку
No, pick another place	Нет, выбрать другое место
Which kind of server do you want?	Какой сервер нужен?
Standard (recommended) - fast, and you can add plugins later	Стандартный (рекомендуется): быстрый, плагины можно добавить позже
Pure Minecraft - exactly like the official game	Чистый Minecraft: точно как в официальной игре
How will your friends join?	Как друзья будут заходить?
Over the internet - easiest, no router settings (free)	Через интернет: проще всего, без настройки роутера (бесплатно)
Over the internet using my router (port forwarding)	Через интернет с помощью роутера (проброс портов)
Only people on my home Wi-Fi	Только те, кто в моей домашней сети Wi-Fi
Does everyone who will join own Minecraft (a paid Microsoft account)?	У всех, кто зайдёт, есть лицензионный Minecraft (платный аккаунт Microsoft)?
YES = safest, recommended.	ДА = безопаснее всего, рекомендуется.
NO  = anyone can join with any name (only for friends you trust).	НЕТ = любой может зайти под любым именем (только для доверенных друзей).
Yes	Да
No	Нет
Finding the newest version ...	Ищу новейшую версию ...
Want to change more things (server message, icon, mods, whitelist, world...)?	Хочешь изменить что-то ещё (сообщение, значок, моды, белый список, мир...)?
Most people choose No - you can still do that later.	Большинство выбирает «Нет» — это можно сделать и позже.
Minecraft EULA	Лицензионное соглашение Minecraft (EULA)
To run a server you must agree to the Minecraft End User License Agreement:	Чтобы запустить сервер, нужно принять лицензионное соглашение Minecraft:
Do you agree to the EULA?	Ты принимаешь EULA?
Summary	Сводка
Install now?	Установить сейчас?
Installing your Minecraft server	Устанавливаю твой сервер Minecraft
Step 1 of 4 - Checking Java	Шаг 1 из 4: проверка Java
Step 2 of 4 - Downloading Minecraft (this can take a minute)	Шаг 2 из 4: загрузка Minecraft (может занять минуту)
Step 3 of 4 - Setting up internet access	Шаг 3 из 4: настройка доступа из интернета
Step 4 of 4 - Finishing up	Шаг 4 из 4: завершение
Your server is ready	Твой сервер готов
To start your server, run:	Чтобы запустить сервер, выполни:
To stop it, type  stop  in the server window.	Чтобы остановить, введи  stop  в окне сервера.
Friends join with:	Друзья заходят по адресу:
Note: anyone can join with any name. Only share the address with people you trust.	Внимание: любой может зайти под любым именем. Делись адресом только с теми, кому доверяешь.
(Your playit.gg address. Keep playit running while you play.)	(Твой адрес playit.gg. Не закрывай playit, пока играешь.)
(Only on the same Wi-Fi.)	(Только в той же сети Wi-Fi.)
Start the server now?	Запустить сервер сейчас?
All set - have fun!	Всё готово — приятной игры!
Setup cancelled. Nothing was installed.	Настройка отменена. Ничего не установлено.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	Настроить бесплатный туннель playit.gg сейчас по пошаговой инструкции? (около 10 минут, можно и позже)
playit.gg tunnel	Туннель playit.gg
Name:	Название:
Type:	Тип:
Friends:	Друзья:
Accounts:	Аккаунты:
Memory:	Память:
Folder:	Папка:
Standard	Стандартный
Pure Minecraft	Чистый Minecraft
over the internet (free tunnel)	через интернет (бесплатный туннель)
over the internet (router port forwarding)	через интернет (проброс портов)
home Wi-Fi only	только домашний Wi-Fi
everyone needs a Minecraft account	нужен аккаунт Minecraft
anyone can join with any name	любой может зайти под любым именем
Press Enter to close	Нажми Enter, чтобы закрыть
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	Не уверен, что это окно может показать этот язык. Если после выбора вы увидите квадраты или ?, перезапустите и выберите английский (лучше всего работает Windows Terminal из Microsoft Store).
Use this language	Использовать этот язык
Use English instead	Использовать английский
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	Этот терминал не в UTF-8, поэтому язык может отображаться неправильно (квадраты или ?). Продолжить на английском?
Use English	Использовать английский
Try it anyway	Всё равно попробовать
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	Совет: если вместо букв вы видите квадраты, запустите снова с  -Lang en  или используйте Windows Terminal.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	Совет: если вместо букв вы видите квадраты, запустите снова с  --lang en  или используйте терминал с подходящим шрифтом.
none	нет
plugins	плагины
mods	моды
Back	Назад
Customise your server. Pick a category; choose 'done' when finished.	Настройте сервер. Выберите раздел; когда закончите, выберите «готово».
Server name: {0}	Имя сервера: {0}
Server list message with colours: {0}	Сообщение в списке серверов с цветами: {0}
Server icon: {0}	Значок сервера: {0}
Mods: {0} queued	Моды: в очереди {0}
Plugins: {0} queued	Плагины: в очереди {0}
Operators ({0}) and whitelist ({1})	Операторы ({0}) и белый список ({1})
World type, seed, structures, nether, hardcore	Тип мира, сид, структуры, Незер, хардкор
PvP, command blocks, flying, mobs, spawn protection	PvP, командные блоки, полёт, мобы, защита спавна
View / simulation distance: {0} / {1}	Дальность прорисовки / симуляции: {0} / {1}
Resource pack: {0}	Набор ресурсов: {0}
Any other server.properties setting ({0})	Любая другая настройка server.properties ({0})
Auto-restart on crash, backup script	Автоперезапуск при сбое, скрипт резервного копирования
Finished customising	Закончить настройку
Name of your server (e.g. Creeper Cove).	Название сервера (например, Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	Используется в заголовках окон, автозапуске, резервных копиях и, если вы не задали своё, как сообщение в списке серверов.
Server list message (MOTD).	Сообщение в списке серверов (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	Цвета: &0 чёрный &1 тёмно-синий &2 тёмно-зелёный &3 тёмно-бирюзовый &4 тёмно-красный &5 фиолетовый &6 золотой
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 серый &8 тёмно-серый &9 синий &a зелёный &b бирюзовый &c красный &d розовый &e жёлтый &f белый
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	Стили:  &l жирный  &o курсив  &n подчёркнутый  &k хаотичный  &r сброс
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	Используйте \n для второй строки.    Пример: &6&lМой сервер\n&7Добро пожаловать!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	Значок сервера: путь к изображению (png/jpg/gif...) или ссылка https://.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	Автоматически преобразуется в 64x64 пикселя (обрезается по центру до квадрата).
Leave empty for no icon.	Оставьте пустым, чтобы без значка.
File not found: {0}	Файл не найден: {0}
Server icon created (64x64)	Значок сервера создан (64x64)
Checking which popular {0} work with Minecraft {1} ...	Проверяю, какие популярные {0} работают с Minecraft {1} ...
[not updated for {0} yet - newest version will be tried]	[ещё не обновлено для {0} - будет использована новейшая версия]
You already added everything in the popular list. Try the search option for more.	Вы уже добавили всё из списка популярных. Попробуйте поиск, чтобы найти ещё.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} очень новый, поэтому {1} плагин(ов) помечены как не обновлённые. Они часто всё равно работают; выбирайте их, если хотите попробовать.
Pick the {0} you want (Space = tick, Enter = done, A = all)	Выберите нужные {0} (Пробел — отметить, Enter — готово, A — все)
Added {0}	Добавлено: {0}
Add {0}  ({1} queued, loader: {2})	Добавить: {0}  (в очереди {1}, загрузчик: {2})
Add {0}  ({1} queued)	Добавить: {0}  (в очереди {1})
Pick from a list of popular {0}	Выбрать из списка популярных: {0}
Search Modrinth for {0} (compatible with {1})	Искать {0} на Modrinth (совместимые с {1})
Add direct https:// links to .jar files	Добавить прямые https:// ссылки на .jar-файлы
Show / remove queued {0}	Показать / удалить {0} из очереди
Done with {0}	Закончить с: {0}
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Поиск на Modrinth ({0} для Minecraft {1}). Примеры: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	Поиск на Modrinth не удался.
Nothing found for '{0}' that works with Minecraft {1}.	По запросу «{0}» ничего не найдено для Minecraft {1}.
Results for '{0}':	Результаты для «{0}»:
Added '{0}' (and any required dependencies).	Добавлено «{0}» (и все необходимые зависимости).
Direct https:// links to .jar files, separated by spaces.	Прямые https:// ссылки на .jar-файлы, через пробел.
Only use links from sources you trust - these files run on your server.	Используйте ссылки только из надёжных источников: эти файлы выполняются на вашем сервере.
Skipping '{0}' (must start with https://)	Пропускаю «{0}» (должно начинаться с https://)
Nothing queued yet.	В очереди пока ничего нет.
Back (keep everything)	Назад (всё оставить)
Pick one to REMOVE from the install list:	Выберите, что УДАЛИТЬ из списка установки:
Skipping invalid name '{0}'	Пропускаю недопустимое имя «{0}»
Operators (admins). Minecraft usernames separated by spaces or commas.	Операторы (администраторы). Ники Minecraft через пробел или запятую.
Ops can use all commands.	Операторы могут использовать все команды.
Whitelist: only these players may join. Usernames separated by spaces or commas.	Белый список: заходить могут только эти игроки. Ники через пробел или запятую.
Leave empty to keep the whitelist as chosen earlier.	Оставьте пустым, чтобы сохранить выбранный ранее белый список.
Could not look up '{0}' - add later with: whitelist add {0}	Не удалось найти «{0}» - добавьте позже командой: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	Не удалось найти «{0}» - добавьте позже командой: op {0}
World type:	Тип мира:
Normal terrain	Обычный рельеф
Superflat	Суперплоский
Large biomes	Крупные биомы
Amplified (tall mountains)	Усиленный (высокие горы)
World seed (empty = random):	Сид мира (пусто = случайный):
World folder name:	Имя папки мира:
Generate structures (villages, strongholds, ...)?	Генерировать структуры (деревни, крепости, ...)?
Allow the Nether?	Разрешить Незер?
Hardcore mode? (one life, forced hard difficulty)	Режим хардкор? (одна жизнь, принудительно сложная сложность)
Allow player-vs-player combat (PvP)?	Разрешить бои между игроками (PvP)?
Enable command blocks?	Включить командные блоки?
Allow flying (needed for some mods; otherwise flight is kicked)?	Разрешить полёт (нужно для некоторых модов; иначе за полёт кикают)?
Spawn animals?	Появление животных?
Spawn monsters?	Появление монстров?
Spawn villagers?	Появление жителей?
Force everyone into the default game mode on every join?	Принудительно ставить всем режим игры по умолчанию при каждом входе?
Spawn protection radius in blocks (0 = off):	Радиус защиты спавна в блоках (0 = выкл.):
Kick idle players after N minutes (0 = never):	Кикать неактивных игроков через N минут (0 = никогда):
View distance in chunks (2-32). Lower = faster:	Дальность прорисовки в чанках (2-32). Меньше = быстрее:
Simulation distance in chunks (2-32). Lower = faster:	Дальность симуляции в чанках (2-32). Меньше = быстрее:
Please enter a number from {0} to {1}. Kept: {2}	Введите число от {0} до {1}. Оставлено: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	Набор ресурсов сервера: прямая https:// ссылка на .zip (пусто = нет).
Players are offered it when they join. Its checksum is calculated at install time.	Предлагается игрокам при входе. Контрольная сумма вычисляется при установке.
That is not a link. Kept: {0}	Это не ссылка. Оставлено: {0}
Kick players who decline the resource pack?	Кикать игроков, отказавшихся от набора ресурсов?
Any other server.properties setting as key=value, separated by spaces.	Любая другая настройка server.properties в виде ключ=значение, через пробел.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	Пример: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	Пропускаю «{0}» (используйте ключ=значение)
Restart the server automatically if it crashes?	Автоматически перезапускать сервер при сбое?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	Создать скрипт резервного копирования (архивирует мир в папку backups, хранит 10 последних)?
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	Загрузчики модов нельзя сочетать здесь с конфигурацией Velocity. (Плагины Paper можно — выберите PaperMC.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla сам не поддерживает моды. Выберите загрузчик модов (он заменит обычный сервер Vanilla):
Fabric - lightweight, huge mod library (recommended)	Fabric — лёгкий, огромная библиотека модов (рекомендуется)
NeoForge - big content mods (1.20.2+)	NeoForge — крупные контентные моды (1.20.2+)
Forge - classic loader (1.17+)	Forge — классический загрузчик (1.17+)
Plain Vanilla, no mods	Чистый Vanilla, без модов
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	У {0} нет серверной версии для Minecraft {1}. Выберите другой загрузчик или другую версию Minecraft.
Modrinth lookup failed for '{0}'.	Не удалось получить «{0}» с Modrinth.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	«{0}» ещё не отмечен для {1} — добавлена его новейшая версия ({2}). Возможно, всё равно заработает.
'{0}' has no download for {1} on this loader.	У «{0}» нет загрузки для {1} с этим загрузчиком.
Newest (recommended)	Новейшая (рекомендуется)
Type a specific older version	Ввести конкретную старую версию
Which Minecraft version? (newest first)	Какая версия Minecraft? (сначала новейшие)
Type the exact Minecraft version (e.g. 1.20.1):	Введите точную версию Minecraft (например, 1.20.1):
That version is not available. Pick one from the list instead.	Эта версия недоступна. Выберите версию из списка.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	Должны ли игроки Bedrock (телефоны, консоли, Windows 10/11) тоже иметь возможность заходить?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	Они заходят через бесплатное дополнение Geyser, поэтому аккаунт Java им не нужен. Требуется Стандартный сервер (Paper) — он выбирается за вас. К именам Bedrock спереди добавляется точка (например, .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	Разрешить заходить и игрокам Bedrock (Geyser + Floodgate)?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Игроки Bedrock Edition (телефоны, консоли, Windows 10/11) смогут заходить без аккаунта Java. Нужен PaperMC; открывается UDP-порт 19132. К именам игроков Bedrock спереди добавляется точка (например, .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Переключено на Стандартный сервер (PaperMC), так как он нужен для поддержки Bedrock.
Downloading Geyser and Floodgate (Bedrock support) ...	Загрузка Geyser и Floodgate (поддержка Bedrock) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Поддержка Bedrock установлена (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	могут заходить и телефоны, консоли и Windows 10/11
Bedrock players (phones, consoles, Windows 10/11) join with:	Игроки Bedrock (телефоны, консоли, Windows 10/11) заходят по адресу:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(В Minecraft Bedrock: Играть > Серверы > Добавить сервер. К их именам спереди добавляется точка, например .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	Совет: сначала остановите сервер (введите  stop  в его окне). Изменения применяются при запуске.
What do you want to change?	Что вы хотите изменить?
Server icon	Значок сервера
Add plugins	Добавить плагины
Add mods	Добавить моды
Remove plugins	Удалить плагины
Remove mods	Удалить моды
Any other server.properties setting	Любая другая настройка server.properties
Change the Minecraft version (now {0})	Сменить версию Minecraft (сейчас {0})
Bedrock players: ON (Geyser + Floodgate)	Игроки Bedrock: ВКЛ (Geyser + Floodgate)
Bedrock players: off	Игроки Bedrock: выкл
Make a backup now	Сделать резервную копию сейчас
Saved.	Сохранено.
All done. Start (or restart) your server to use the changes.	Готово. Запустите (или перезапустите) сервер, чтобы применить изменения.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	Смена сида, типа мира или имени папки влияет только на НОВЫЙ мир. Текущий мир останется как есть.
Backup saved: {0}	Резервная копия сохранена: {0}
Making a backup first ...	Сначала делаю резервную копию ...
The backup failed - stopping here so nothing is lost.	Резервная копия не удалась — останавливаюсь, чтобы ничего не потерять.
Which server do you want to change?	Какой сервер вы хотите изменить?
Pick another folder ...	Выбрать другую папку ...
Type the folder of your server (the one that contains start-all):	Введите папку сервера (ту, где лежит start-all):
That folder does not look like a server made by this tool.	Эта папка не похожа на сервер, созданный этим инструментом.
{0} file(s) placed in {1}	Файлов размещено: {0}, папка: {1}
Nothing is installed in this folder yet.	В этой папке пока ничего не установлено.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	Отметьте то, что нужно УДАЛИТЬ (оно перемещается в папку removed, а не стирается)
Removed {0}	Удалено: {0}
Fetching version list ...	Получаю список версий ...
Could not get the version list (is the internet working?).	Не удалось получить список версий (работает ли интернет?).
That is the version you already have.	Это версия, которая у вас уже есть.
Change Minecraft from {0} to {1}?	Сменить Minecraft с {0} на {1}?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	Миры нельзя вернуть на более старую версию, поэтому сначала делается полная резервная копия. После этого плагины и моды, возможно, придётся обновить.
Now on Minecraft {0}	Теперь Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	Если плагин или мод перестанет работать с новой версией, обновите или удалите его в этом меню. Чтобы вернуться назад, восстановите копию из папки backups.
This loader has no release for that version.	У этого загрузчика нет выпуска для этой версии.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	Поддержка Bedrock ВКЛЮЧЕНА. Выключить? (Geyser и Floodgate будут перемещены в папку removed.)
Bedrock support turned off.	Поддержка Bedrock выключена.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	Поддержка Bedrock здесь требует обычного сервера PaperMC (не Velocity, Fabric или Forge).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	Разрешить заходить и игрокам Bedrock (телефоны, консоли, Windows 10/11)?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Добавляются Geyser и Floodgate. Им нужен PaperMC. К именам Bedrock спереди добавляется точка (например, .Steve). Используется UDP-порт {0}.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	Ваш сервер — Vanilla. Перейти на PaperMC (та же версия, тот же мир)? Сначала будет сделана полная резервная копия.
PaperMC has no build for this version.	У PaperMC нет сборки для этой версии.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Игрокам Bedrock нужен доступный UDP-порт {0}. С playit.gg запустите  bash mc-setup.sh --tunnel-guide , чтобы добавить туннель Bedrock; на роутере пробросьте также UDP {0}.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Игрокам Bedrock нужен доступный UDP-порт {0}. С playit.gg запустите  powershell -File mc-setup.ps1 -TunnelGuide , чтобы добавить туннель Bedrock; на роутере пробросьте также UDP {0}.
In my home folder	В моей домашней папке
EOF
}
lang_data_zh() { cat <<'EOF'
Let's set up your Minecraft server	来设置你的 Minecraft 服务器吧
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	用方向键和回车选择。随时按 Ctrl+C 退出。
Nothing is installed until you confirm at the end.	在最后确认之前不会安装任何东西。
How do you want to set up?	你想怎么设置？
Simple - a few easy questions, everything else is chosen for you	简单：回答几个问题，其余自动选择
Advanced - choose every option yourself	高级：自己选择每个选项
What do you want to call your server?	你想给服务器起什么名字？
Where should your server be saved? A new folder with your server's name is created there.	服务器保存在哪里？将在那里新建一个以服务器名命名的文件夹。
Next to this script (recommended)	放在本脚本旁边（推荐）
On my Desktop	放在桌面
In my Documents folder	放在“文档”文件夹
Somewhere else (type a folder)	其他位置（输入文件夹）
Somewhere else (browse or type a folder)	其他位置（浏览或输入文件夹）
Your server will be installed in:	服务器将安装到：
Yes, use this folder	是，使用这个文件夹
No, pick another place	否，选择其他位置
Which kind of server do you want?	你想要哪种服务器？
Standard (recommended) - fast, and you can add plugins later	标准（推荐）：速度快，以后可添加插件
Pure Minecraft - exactly like the official game	纯净 Minecraft：和官方游戏完全一样
How will your friends join?	你的朋友怎么加入？
Over the internet - easiest, no router settings (free)	通过互联网：最简单，无需设置路由器（免费）
Over the internet using my router (port forwarding)	通过互联网，使用我的路由器（端口转发）
Only people on my home Wi-Fi	仅限我家 Wi-Fi 内的人
Does everyone who will join own Minecraft (a paid Microsoft account)?	所有要加入的人都拥有正版 Minecraft（付费微软账号）吗？
YES = safest, recommended.	是 = 最安全，推荐。
NO  = anyone can join with any name (only for friends you trust).	否 = 任何人都能用任意名字加入（仅限信任的朋友）。
Yes	是
No	否
Finding the newest version ...	正在查找最新版本 ...
Want to change more things (server message, icon, mods, whitelist, world...)?	想更改更多设置吗（服务器消息、图标、模组、白名单、世界…）？
Most people choose No - you can still do that later.	大多数人选“否”，以后仍可更改。
Minecraft EULA	Minecraft 最终用户许可协议（EULA）
To run a server you must agree to the Minecraft End User License Agreement:	要运行服务器，你必须同意 Minecraft 最终用户许可协议：
Do you agree to the EULA?	你同意 EULA 吗？
Summary	摘要
Install now?	现在安装吗？
Installing your Minecraft server	正在安装你的 Minecraft 服务器
Step 1 of 4 - Checking Java	第 1 步，共 4 步：检查 Java
Step 2 of 4 - Downloading Minecraft (this can take a minute)	第 2 步，共 4 步：下载 Minecraft（可能需要一分钟）
Step 3 of 4 - Setting up internet access	第 3 步，共 4 步：设置互联网访问
Step 4 of 4 - Finishing up	第 4 步，共 4 步：收尾
Your server is ready	你的服务器已就绪
To start your server, run:	要启动服务器，请运行：
To stop it, type  stop  in the server window.	要停止服务器，请在服务器窗口中输入  stop。
Friends join with:	朋友通过以下地址加入：
Note: anyone can join with any name. Only share the address with people you trust.	注意：任何人都能用任意名字加入。只把地址分享给你信任的人。
(Your playit.gg address. Keep playit running while you play.)	（这是你的 playit.gg 地址。游戏期间请保持 playit 运行。）
(Only on the same Wi-Fi.)	（仅限同一 Wi-Fi。）
Start the server now?	现在启动服务器吗？
All set - have fun!	全部完成，玩得开心！
Setup cancelled. Nothing was installed.	设置已取消，未安装任何东西。
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	现在按分步指南设置免费的 playit.gg 隧道吗？（约 10 分钟，也可以以后再做）
playit.gg tunnel	playit.gg 隧道
Name:	名称：
Type:	类型：
Friends:	朋友：
Accounts:	账号：
Memory:	内存：
Folder:	文件夹：
Standard	标准
Pure Minecraft	纯净 Minecraft
over the internet (free tunnel)	通过互联网（免费隧道）
over the internet (router port forwarding)	通过互联网（路由器端口转发）
home Wi-Fi only	仅限家庭 Wi-Fi
everyone needs a Minecraft account	每个人都需要 Minecraft 账号
anyone can join with any name	任何人都能用任意名字加入
Press Enter to close	按回车关闭
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	不确定此窗口能否显示这种语言。如果选择后看到方块或问号，请重新启动并选择英语（推荐使用 Microsoft Store 中的 Windows Terminal）。
Use this language	使用此语言
Use English instead	改用英语
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	此终端未设置为 UTF-8，这种语言可能显示异常（方块或?）。是否改用英语继续？
Use English	使用英语
Try it anyway	仍然尝试
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	提示：如果看到方块而不是文字，请使用  -Lang en  重新运行，或使用 Windows Terminal。
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	提示：如果看到方块而不是文字，请使用  --lang en  重新运行，或使用支持该语言字体的终端。
none	无
plugins	插件
mods	模组
Back	返回
Customise your server. Pick a category; choose 'done' when finished.	自定义你的服务器。选择一个类别；完成后选择“完成”。
Server name: {0}	服务器名称：{0}
Server list message with colours: {0}	服务器列表消息（带颜色）：{0}
Server icon: {0}	服务器图标：{0}
Mods: {0} queued	模组：已排队 {0} 个
Plugins: {0} queued	插件：已排队 {0} 个
Operators ({0}) and whitelist ({1})	管理员（{0}）和白名单（{1}）
World type, seed, structures, nether, hardcore	世界类型、种子、结构、下界、极限模式
PvP, command blocks, flying, mobs, spawn protection	PvP、命令方块、飞行、生物、出生点保护
View / simulation distance: {0} / {1}	视距 / 模拟距离：{0} / {1}
Resource pack: {0}	资源包：{0}
Any other server.properties setting ({0})	任何其他 server.properties 设置（{0}）
Auto-restart on crash, backup script	崩溃自动重启、备份脚本
Finished customising	完成自定义
Name of your server (e.g. Creeper Cove).	你的服务器名称（例如 Creeper Cove）。
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	用于窗口标题、自动启动项、备份；如果你没有另外设置，也会作为服务器列表中的消息。
Server list message (MOTD).	服务器列表消息（MOTD）。
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	颜色：&0 黑 &1 深蓝 &2 深绿 &3 深青 &4 深红 &5 紫 &6 金
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 灰 &8 深灰 &9 蓝 &a 绿 &b 青 &c 红 &d 粉 &e 黄 &f 白
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	样式：&l 粗体  &o 斜体  &n 下划线  &k 乱码  &r 重置
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	用 \n 换到第二行。    示例：&6&l我的服务器\n&7欢迎！
Server icon: path to an image (png/jpg/gif...) or an https:// link.	服务器图标：图片路径（png/jpg/gif...）或 https:// 链接。
It is converted to 64x64 pixels automatically (centre-cropped to a square).	会自动转换为 64x64 像素（居中裁剪为正方形）。
Leave empty for no icon.	留空表示不使用图标。
File not found: {0}	找不到文件：{0}
Server icon created (64x64)	已创建服务器图标（64x64）
Checking which popular {0} work with Minecraft {1} ...	正在检查哪些热门{0}适用于 Minecraft {1} ...
[not updated for {0} yet - newest version will be tried]	[尚未适配 {0}，将尝试最新版本]
You already added everything in the popular list. Try the search option for more.	热门列表里的内容你都添加过了。试试搜索来找更多。
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} 非常新，有 {1} 个插件被标记为尚未更新。它们通常仍可使用；想试的话可以选上。
Pick the {0} you want (Space = tick, Enter = done, A = all)	选择你想要的{0}（空格 = 勾选，回车 = 完成，A = 全选）
Added {0}	已添加 {0}
Add {0}  ({1} queued, loader: {2})	添加{0}（已排队 {1} 个，加载器：{2}）
Add {0}  ({1} queued)	添加{0}（已排队 {1} 个）
Pick from a list of popular {0}	从热门{0}列表中选择
Search Modrinth for {0} (compatible with {1})	在 Modrinth 搜索{0}（兼容 {1}）
Add direct https:// links to .jar files	添加指向 .jar 文件的 https:// 直链
Show / remove queued {0}	查看 / 移除已排队的{0}
Done with {0}	完成{0}设置
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	在 Modrinth 搜索（适用于 Minecraft {1} 的{0}）。例如：worldedit、essentialsx、lithium、luckperms
Modrinth search failed.	Modrinth 搜索失败。
Nothing found for '{0}' that works with Minecraft {1}.	没有找到适用于 Minecraft {1} 的“{0}”。
Results for '{0}':	“{0}”的搜索结果：
Added '{0}' (and any required dependencies).	已添加“{0}”（以及所有必需的依赖项）。
Direct https:// links to .jar files, separated by spaces.	指向 .jar 文件的 https:// 直链，用空格分隔。
Only use links from sources you trust - these files run on your server.	只使用你信任来源的链接——这些文件会在你的服务器上运行。
Skipping '{0}' (must start with https://)	跳过“{0}”（必须以 https:// 开头）
Nothing queued yet.	目前没有排队的项目。
Back (keep everything)	返回（保留全部）
Pick one to REMOVE from the install list:	选择要从安装列表中移除的一项：
Skipping invalid name '{0}'	跳过无效名称“{0}”
Operators (admins). Minecraft usernames separated by spaces or commas.	管理员（OP）。Minecraft 用户名，用空格或逗号分隔。
Ops can use all commands.	管理员可以使用所有命令。
Whitelist: only these players may join. Usernames separated by spaces or commas.	白名单：只有这些玩家可以加入。用户名用空格或逗号分隔。
Leave empty to keep the whitelist as chosen earlier.	留空则保留之前选择的白名单。
Could not look up '{0}' - add later with: whitelist add {0}	无法查询“{0}”——之后可用此命令添加：whitelist add {0}
Could not look up '{0}' - add later with: op {0}	无法查询“{0}”——之后可用此命令添加：op {0}
World type:	世界类型：
Normal terrain	普通地形
Superflat	超平坦
Large biomes	巨型生物群系
Amplified (tall mountains)	放大化（高山）
World seed (empty = random):	世界种子（留空 = 随机）：
World folder name:	世界文件夹名称：
Generate structures (villages, strongholds, ...)?	生成结构（村庄、要塞等）？
Allow the Nether?	允许下界吗？
Hardcore mode? (one life, forced hard difficulty)	极限模式？（只有一条命，强制困难难度）
Allow player-vs-player combat (PvP)?	允许玩家之间战斗（PvP）吗？
Enable command blocks?	启用命令方块吗？
Allow flying (needed for some mods; otherwise flight is kicked)?	允许飞行吗？（部分模组需要；否则飞行会被踢出）
Spawn animals?	生成动物吗？
Spawn monsters?	生成怪物吗？
Spawn villagers?	生成村民吗？
Force everyone into the default game mode on every join?	每次加入时强制所有人使用默认游戏模式吗？
Spawn protection radius in blocks (0 = off):	出生点保护半径（方块数，0 = 关闭）：
Kick idle players after N minutes (0 = never):	闲置 N 分钟后踢出玩家（0 = 从不）：
View distance in chunks (2-32). Lower = faster:	视距（区块数，2-32）。越小越快：
Simulation distance in chunks (2-32). Lower = faster:	模拟距离（区块数，2-32）。越小越快：
Please enter a number from {0} to {1}. Kept: {2}	请输入 {0} 到 {1} 之间的数字。保持为：{2}
Server resource pack: direct https:// link to a .zip (empty = none).	服务器资源包：指向 .zip 的 https:// 直链（留空 = 无）。
Players are offered it when they join. Its checksum is calculated at install time.	玩家加入时会收到提示。校验和会在安装时计算。
That is not a link. Kept: {0}	这不是链接。保持为：{0}
Kick players who decline the resource pack?	踢出拒绝资源包的玩家吗？
Any other server.properties setting as key=value, separated by spaces.	任何其他 server.properties 设置，格式为 键=值，用空格分隔。
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	示例：rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	跳过“{0}”（请使用 键=值）
Restart the server automatically if it crashes?	服务器崩溃时自动重启吗？
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	创建备份脚本吗？（把世界打包到 backups 文件夹，保留最新的 10 个）
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	这里无法将模组加载器与 Velocity 方案组合。（Paper 插件可以——请选择 PaperMC。）
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	原版本身不支持模组。请选择一个模组加载器（它会替换普通的原版服务器）：
Fabric - lightweight, huge mod library (recommended)	Fabric——轻量，模组库庞大（推荐）
NeoForge - big content mods (1.20.2+)	NeoForge——大型内容模组（1.20.2+）
Forge - classic loader (1.17+)	Forge——经典加载器（1.17+）
Plain Vanilla, no mods	纯原版，无模组
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} 没有适用于 Minecraft {1} 的服务器版本。请选择其他加载器或其他 Minecraft 版本。
Modrinth lookup failed for '{0}'.	在 Modrinth 查询“{0}”失败。
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	“{0}”尚未标注支持 {1}——已添加其最新版本（{2}）。它仍可能可用。
'{0}' has no download for {1} on this loader.	“{0}”在此加载器上没有适用于 {1} 的下载。
Newest (recommended)	最新（推荐）
Type a specific older version	输入指定的旧版本
Which Minecraft version? (newest first)	使用哪个 Minecraft 版本？（最新的在前）
Type the exact Minecraft version (e.g. 1.20.1):	请输入确切的 Minecraft 版本（例如 1.20.1）：
That version is not available. Pick one from the list instead.	该版本不可用。请从列表中选择。
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	要让 Bedrock 玩家（手机、主机、Windows 10/11）也能加入吗？
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	他们通过名为 Geyser 的免费附加组件加入，因此不需要 Java 账号。这需要标准（Paper）服务器，会自动为你选择。Bedrock 玩家的名字前会加一个点（例如 .Steve）。
Also let Bedrock players join (Geyser + Floodgate)?	也允许 Bedrock 玩家加入吗（Geyser + Floodgate）？
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Bedrock 版玩家（手机、主机、Windows 10/11）无需 Java 账号即可加入。需要 PaperMC，并会开放 UDP 端口 19132。Bedrock 玩家的名字前会加一个点（例如 .Steve）。
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	已切换到标准（PaperMC）服务器，因为 Bedrock 支持需要它。
Downloading Geyser and Floodgate (Bedrock support) ...	正在下载 Geyser 和 Floodgate（Bedrock 支持）...
Bedrock support installed (Geyser + Floodgate, UDP {0})	已安装 Bedrock 支持（Geyser + Floodgate，UDP {0}）
Bedrock:	Bedrock：
phones, consoles and Windows 10/11 can join too	手机、主机和 Windows 10/11 也能加入
Bedrock players (phones, consoles, Windows 10/11) join with:	Bedrock 玩家（手机、主机、Windows 10/11）使用以下地址加入：
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	（在 Minecraft Bedrock 中：游玩 > 服务器 > 添加服务器。他们的名字前会加一个点，如 .Steve。）
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	提示：请先停止服务器（在其窗口中输入  stop）。更改会在服务器启动时生效。
What do you want to change?	你想更改什么？
Server icon	服务器图标
Add plugins	添加插件
Add mods	添加模组
Remove plugins	移除插件
Remove mods	移除模组
Any other server.properties setting	任何其他 server.properties 设置
Change the Minecraft version (now {0})	更改 Minecraft 版本（当前 {0}）
Bedrock players: ON (Geyser + Floodgate)	Bedrock 玩家：开（Geyser + Floodgate）
Bedrock players: off	Bedrock 玩家：关
Make a backup now	立即备份
Saved.	已保存。
All done. Start (or restart) your server to use the changes.	全部完成。启动（或重启）服务器即可使用更改。
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	更改种子、世界类型或世界文件夹名称只会影响新世界。你现有的世界保持不变。
Backup saved: {0}	备份已保存：{0}
Making a backup first ...	先进行备份 ...
The backup failed - stopping here so nothing is lost.	备份失败——到此为止，以免丢失任何内容。
Which server do you want to change?	你想更改哪个服务器？
Pick another folder ...	选择其他文件夹 ...
Type the folder of your server (the one that contains start-all):	请输入服务器所在的文件夹（包含 start-all 的那个）：
That folder does not look like a server made by this tool.	该文件夹看起来不是由本工具创建的服务器。
{0} file(s) placed in {1}	已将 {0} 个文件放入 {1}
Nothing is installed in this folder yet.	此文件夹中还没有安装任何内容。
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	勾选要移除的项目（它们会被移到名为 removed 的文件夹，不会被删除）
Removed {0}	已移除 {0}
Fetching version list ...	正在获取版本列表 ...
Could not get the version list (is the internet working?).	无法获取版本列表（网络正常吗？）。
That is the version you already have.	这就是你已有的版本。
Change Minecraft from {0} to {1}?	将 Minecraft 从 {0} 更改为 {1}？
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	世界无法回退到旧版本，所以会先做一次完整备份。之后插件和模组可能需要更新。
Now on Minecraft {0}	现在使用 Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	如果某个插件或模组在新版本下无法使用，请在此菜单中更新或移除它。若要回退，请从 backups 文件夹恢复备份。
This loader has no release for that version.	此加载器没有适用于该版本的发行版。
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	Bedrock 支持已开启。要关闭吗？（Geyser 和 Floodgate 会被移到名为 removed 的文件夹。）
Bedrock support turned off.	已关闭 Bedrock 支持。
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	这里的 Bedrock 支持需要普通的 PaperMC 服务器（不能是 Velocity、Fabric 或 Forge）。
Let Bedrock players (phones, consoles, Windows 10/11) join too?	也允许 Bedrock 玩家（手机、主机、Windows 10/11）加入吗？
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	将添加 Geyser 和 Floodgate，它们需要 PaperMC。Bedrock 玩家的名字前会加一个点（例如 .Steve）。使用 UDP 端口 {0}。
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	你的服务器是原版（Vanilla）。要切换到 PaperMC（相同版本、相同世界）吗？会先做一次完整备份。
PaperMC has no build for this version.	PaperMC 没有适用于此版本的构建。
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock 玩家需要能访问 UDP 端口 {0}。使用 playit.gg 时，运行  bash mc-setup.sh --tunnel-guide  添加 Bedrock 隧道；使用路由器时，也要转发 UDP {0}。
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock 玩家需要能访问 UDP 端口 {0}。使用 playit.gg 时，运行  powershell -File mc-setup.ps1 -TunnelGuide  添加 Bedrock 隧道；使用路由器时，也要转发 UDP {0}。
In my home folder	在我的主文件夹
EOF
}
lang_data_ja() { cat <<'EOF'
Let's set up your Minecraft server	Minecraftサーバーをセットアップしましょう
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	矢印キーとEnterで操作します。Ctrl+Cでいつでも終了できます。
Nothing is installed until you confirm at the end.	最後に確認するまで、何もインストールされません。
How do you want to set up?	どのようにセットアップしますか？
Simple - a few easy questions, everything else is chosen for you	かんたん：いくつかの質問だけ。あとはおまかせ
Advanced - choose every option yourself	上級：すべての設定を自分で選ぶ
What do you want to call your server?	サーバーの名前を入力してください
Where should your server be saved? A new folder with your server's name is created there.	サーバーの保存先は？サーバー名の新しいフォルダーが作成されます。
Next to this script (recommended)	このスクリプトの隣（おすすめ）
On my Desktop	デスクトップ
In my Documents folder	ドキュメントフォルダー
Somewhere else (type a folder)	その他（フォルダーを入力）
Somewhere else (browse or type a folder)	その他（参照またはフォルダーを入力）
Your server will be installed in:	サーバーのインストール先：
Yes, use this folder	はい、このフォルダーを使う
No, pick another place	いいえ、別の場所を選ぶ
Which kind of server do you want?	どの種類のサーバーにしますか？
Standard (recommended) - fast, and you can add plugins later	標準（おすすめ）：高速で、後からプラグインを追加できます
Pure Minecraft - exactly like the official game	ピュアMinecraft：公式ゲームとまったく同じ
How will your friends join?	友達はどうやって参加しますか？
Over the internet - easiest, no router settings (free)	インターネット経由：いちばん簡単、ルーター設定不要（無料）
Over the internet using my router (port forwarding)	インターネット経由・ルーター使用（ポート開放）
Only people on my home Wi-Fi	自宅のWi-Fi内の人だけ
Does everyone who will join own Minecraft (a paid Microsoft account)?	参加する全員がMinecraftを購入済み（有料のMicrosoftアカウント）ですか？
YES = safest, recommended.	はい＝いちばん安全（おすすめ）。
NO  = anyone can join with any name (only for friends you trust).	いいえ＝誰でも好きな名前で参加できます（信頼できる友達だけに）。
Yes	はい
No	いいえ
Finding the newest version ...	最新バージョンを確認中 ...
Want to change more things (server message, icon, mods, whitelist, world...)?	他の設定も変更しますか（メッセージ、アイコン、MOD、ホワイトリスト、ワールド…）？
Most people choose No - you can still do that later.	多くの人は「いいえ」を選びます。後からでも変更できます。
Minecraft EULA	Minecraft EULA（使用許諾契約）
To run a server you must agree to the Minecraft End User License Agreement:	サーバーを動かすには、Minecraftの使用許諾契約に同意する必要があります：
Do you agree to the EULA?	EULAに同意しますか？
Summary	概要
Install now?	今すぐインストールしますか？
Installing your Minecraft server	Minecraftサーバーをインストール中
Step 1 of 4 - Checking Java	ステップ 1/4：Javaの確認
Step 2 of 4 - Downloading Minecraft (this can take a minute)	ステップ 2/4：Minecraftをダウンロード中（1分ほどかかります）
Step 3 of 4 - Setting up internet access	ステップ 3/4：インターネット接続の設定
Step 4 of 4 - Finishing up	ステップ 4/4：仕上げ
Your server is ready	サーバーの準備ができました
To start your server, run:	サーバーを起動するには、次を実行：
To stop it, type  stop  in the server window.	停止するには、サーバーウィンドウで  stop  と入力します。
Friends join with:	友達はこのアドレスで参加：
Note: anyone can join with any name. Only share the address with people you trust.	注意：誰でも好きな名前で参加できます。信頼できる人にだけアドレスを共有してください。
(Your playit.gg address. Keep playit running while you play.)	（あなたのplayit.ggアドレスです。プレイ中はplayitを起動したままにしてください。）
(Only on the same Wi-Fi.)	（同じWi-Fi内のみ。）
Start the server now?	今すぐサーバーを起動しますか？
All set - have fun!	準備完了です。楽しんで！
Setup cancelled. Nothing was installed.	セットアップを中止しました。何もインストールされていません。
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	手順ガイドで無料のplayit.ggトンネルを今設定しますか？（約10分。後でも可能）
playit.gg tunnel	playit.gg トンネル
Name:	名前：
Type:	種類：
Friends:	友達：
Accounts:	アカウント：
Memory:	メモリ：
Folder:	フォルダー：
Standard	標準
Pure Minecraft	ピュアMinecraft
over the internet (free tunnel)	インターネット経由（無料トンネル）
over the internet (router port forwarding)	インターネット経由（ポート開放）
home Wi-Fi only	自宅のWi-Fiのみ
everyone needs a Minecraft account	全員にMinecraftアカウントが必要
anyone can join with any name	誰でも好きな名前で参加可能
Press Enter to close	Enterキーで閉じる
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	このウィンドウでこの言語を表示できるか不明です。選択後に四角や ? が表示されたら、再起動して英語を選んでください（Microsoft Store の Windows Terminal が最適です）。
Use this language	この言語を使う
Use English instead	代わりに英語を使う
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	このターミナルは UTF-8 ではないため、この言語は正しく表示されないことがあります（四角や ?）。英語で続けますか？
Use English	英語を使う
Try it anyway	それでも試す
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	ヒント：文字が四角で表示される場合は  -Lang en  を付けて再実行するか、Windows Terminal を使ってください。
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	ヒント：文字が四角で表示される場合は  --lang en  を付けて再実行するか、対応フォントのあるターミナルを使ってください。
none	なし
plugins	プラグイン
mods	MOD
Back	戻る
Customise your server. Pick a category; choose 'done' when finished.	サーバーをカスタマイズします。カテゴリを選び、終わったら「完了」を選んでください。
Server name: {0}	サーバー名: {0}
Server list message with colours: {0}	サーバー一覧のメッセージ（色付き）: {0}
Server icon: {0}	サーバーアイコン: {0}
Mods: {0} queued	MOD: {0} 件待機中
Plugins: {0} queued	プラグイン: {0} 件待機中
Operators ({0}) and whitelist ({1})	オペレーター（{0}）とホワイトリスト（{1}）
World type, seed, structures, nether, hardcore	ワールドタイプ、シード、構造物、ネザー、ハードコア
PvP, command blocks, flying, mobs, spawn protection	PvP、コマンドブロック、飛行、モブ、スポーン保護
View / simulation distance: {0} / {1}	描画距離 / シミュレーション距離: {0} / {1}
Resource pack: {0}	リソースパック: {0}
Any other server.properties setting ({0})	その他の server.properties 設定（{0}）
Auto-restart on crash, backup script	クラッシュ時の自動再起動、バックアップスクリプト
Finished customising	カスタマイズを終了
Name of your server (e.g. Creeper Cove).	サーバーの名前（例: Creeper Cove）。
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	ウィンドウのタイトル、自動起動、バックアップに使われ、自分で設定しない場合はサーバー一覧のメッセージにもなります。
Server list message (MOTD).	サーバー一覧のメッセージ（MOTD）。
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	色: &0 黒 &1 濃い青 &2 濃い緑 &3 濃い水色 &4 濃い赤 &5 紫 &6 金
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 灰 &8 濃い灰 &9 青 &a 緑 &b 水色 &c 赤 &d ピンク &e 黄 &f 白
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	スタイル: &l 太字  &o 斜体  &n 下線  &k 難読化  &r リセット
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	\n で2行目に改行します。    例: &6&lMy Server\n&7Welcome!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	サーバーアイコン: 画像のパス（png/jpg/gif...）または https:// のリンク。
It is converted to 64x64 pixels automatically (centre-cropped to a square).	自動的に 64x64 ピクセルに変換されます（中央を正方形に切り抜き）。
Leave empty for no icon.	空欄ならアイコンなしになります。
File not found: {0}	ファイルが見つかりません: {0}
Server icon created (64x64)	サーバーアイコンを作成しました（64x64）
Checking which popular {0} work with Minecraft {1} ...	Minecraft {1} で動く人気の{0}を確認中 ...
[not updated for {0} yet - newest version will be tried]	[{0} 向けには未更新 - 最新版を試します]
You already added everything in the popular list. Try the search option for more.	人気リストのものはすべて追加済みです。検索でさらに探せます。
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} は非常に新しいため、{1} 個のプラグインが未更新と表示されています。多くは問題なく動くので、試したいものを選んでください。
Pick the {0} you want (Space = tick, Enter = done, A = all)	使いたい{0}を選んでください（スペース = チェック、Enter = 完了、A = すべて）
Added {0}	{0} を追加しました
Add {0}  ({1} queued, loader: {2})	{0} を追加（{1} 件待機中、ローダー: {2}）
Add {0}  ({1} queued)	{0} を追加（{1} 件待機中）
Pick from a list of popular {0}	人気の{0}のリストから選ぶ
Search Modrinth for {0} (compatible with {1})	Modrinth で{0}を検索（{1} 対応）
Add direct https:// links to .jar files	.jar ファイルへの直接 https:// リンクを追加
Show / remove queued {0}	待機中の{0}を表示 / 削除
Done with {0}	{0} の設定を終了
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Modrinth で検索（Minecraft {1} 用の{0}）。例: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	Modrinth の検索に失敗しました。
Nothing found for '{0}' that works with Minecraft {1}.	Minecraft {1} で動く「{0}」は見つかりませんでした。
Results for '{0}':	「{0}」の検索結果:
Added '{0}' (and any required dependencies).	「{0}」を追加しました（必要な依存関係も含む）。
Direct https:// links to .jar files, separated by spaces.	.jar ファイルへの直接 https:// リンクをスペース区切りで入力。
Only use links from sources you trust - these files run on your server.	信頼できる提供元のリンクだけを使ってください。これらのファイルはサーバー上で実行されます。
Skipping '{0}' (must start with https://)	「{0}」をスキップ（https:// で始まる必要があります）
Nothing queued yet.	待機中のものはまだありません。
Back (keep everything)	戻る（すべて保持）
Pick one to REMOVE from the install list:	インストール一覧から削除するものを選んでください:
Skipping invalid name '{0}'	無効な名前「{0}」をスキップ
Operators (admins). Minecraft usernames separated by spaces or commas.	オペレーター（管理者）。Minecraft のユーザー名をスペースまたはカンマで区切って入力。
Ops can use all commands.	オペレーターはすべてのコマンドを使えます。
Whitelist: only these players may join. Usernames separated by spaces or commas.	ホワイトリスト: ここにいるプレイヤーだけが参加できます。ユーザー名をスペースまたはカンマで区切って入力。
Leave empty to keep the whitelist as chosen earlier.	空欄なら先ほど選んだホワイトリストのままになります。
Could not look up '{0}' - add later with: whitelist add {0}	「{0}」を検索できませんでした。後で次のコマンドで追加: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	「{0}」を検索できませんでした。後で次のコマンドで追加: op {0}
World type:	ワールドタイプ:
Normal terrain	通常の地形
Superflat	スーパーフラット
Large biomes	大きなバイオーム
Amplified (tall mountains)	アンプリファイド（高い山）
World seed (empty = random):	ワールドのシード（空欄 = ランダム）:
World folder name:	ワールドフォルダ名:
Generate structures (villages, strongholds, ...)?	構造物（村、要塞など）を生成しますか？
Allow the Nether?	ネザーを許可しますか？
Hardcore mode? (one life, forced hard difficulty)	ハードコアモード？（命は1つ、難易度は強制的にハード）
Allow player-vs-player combat (PvP)?	プレイヤー同士の戦闘（PvP）を許可しますか？
Enable command blocks?	コマンドブロックを有効にしますか？
Allow flying (needed for some mods; otherwise flight is kicked)?	飛行を許可しますか？（一部のMODに必要。許可しないと飛行でキックされます）
Spawn animals?	動物をスポーンさせますか？
Spawn monsters?	モンスターをスポーンさせますか？
Spawn villagers?	村人をスポーンさせますか？
Force everyone into the default game mode on every join?	参加するたびに全員をデフォルトのゲームモードにしますか？
Spawn protection radius in blocks (0 = off):	スポーン保護の半径（ブロック数、0 = オフ）:
Kick idle players after N minutes (0 = never):	N 分間操作がないプレイヤーをキック（0 = しない）:
View distance in chunks (2-32). Lower = faster:	描画距離（チャンク、2-32）。小さいほど軽い:
Simulation distance in chunks (2-32). Lower = faster:	シミュレーション距離（チャンク、2-32）。小さいほど軽い:
Please enter a number from {0} to {1}. Kept: {2}	{0} から {1} の数字を入力してください。変更なし: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	サーバーのリソースパック: .zip への直接 https:// リンク（空欄 = なし）。
Players are offered it when they join. Its checksum is calculated at install time.	参加時にプレイヤーへ提案されます。チェックサムはインストール時に計算されます。
That is not a link. Kept: {0}	リンクではありません。変更なし: {0}
Kick players who decline the resource pack?	リソースパックを拒否したプレイヤーをキックしますか？
Any other server.properties setting as key=value, separated by spaces.	その他の server.properties の設定を キー=値 の形でスペース区切りで入力。
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	例: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	「{0}」をスキップ（キー=値 の形で入力）
Restart the server automatically if it crashes?	クラッシュしたら自動でサーバーを再起動しますか？
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	バックアップスクリプトを作成しますか？（ワールドを backups フォルダに圧縮し、最新の10件を保持）
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	ここでは Mod ローダーと Velocity 構成は組み合わせられません。（Paper のプラグインなら可能です。PaperMC を選んでください。）
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla 自体は MOD に対応していません。MOD ローダーを選んでください（通常の Vanilla サーバーの代わりになります）:
Fabric - lightweight, huge mod library (recommended)	Fabric - 軽量で MOD が豊富（おすすめ）
NeoForge - big content mods (1.20.2+)	NeoForge - 大型コンテンツ MOD 向け（1.20.2+）
Forge - classic loader (1.17+)	Forge - 定番のローダー（1.17+）
Plain Vanilla, no mods	素の Vanilla（MOD なし）
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} には Minecraft {1} 向けのサーバー版がありません。別のローダーか別の Minecraft バージョンを選んでください。
Modrinth lookup failed for '{0}'.	Modrinth で「{0}」を取得できませんでした。
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	「{0}」はまだ {1} 対応と記載されていません。最新版（{2}）を追加しました。動く可能性はあります。
'{0}' has no download for {1} on this loader.	「{0}」にはこのローダー用の {1} 向けダウンロードがありません。
Newest (recommended)	最新（おすすめ）
Type a specific older version	特定の古いバージョンを入力
Which Minecraft version? (newest first)	どの Minecraft バージョンにしますか？（新しい順）
Type the exact Minecraft version (e.g. 1.20.1):	Minecraft のバージョンを正確に入力してください（例: 1.20.1）:
That version is not available. Pick one from the list instead.	そのバージョンは利用できません。一覧から選んでください。
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	Bedrock 版のプレイヤー（スマホ、ゲーム機、Windows 10/11）も参加できるようにしますか？
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	無料のアドオン Geyser を通じて参加するため、Java アカウントは不要です。標準（Paper）サーバーが必要で、自動的に選ばれます。Bedrock の名前の先頭にはドットが付きます（例: .Steve）。
Also let Bedrock players join (Geyser + Floodgate)?	Bedrock 版のプレイヤーも参加できるようにしますか？（Geyser + Floodgate）
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Bedrock Edition のプレイヤー（スマホ、ゲーム機、Windows 10/11）が Java アカウントなしで参加できます。PaperMC が必要で、UDP ポート 19132 を開きます。Bedrock のプレイヤー名の先頭にはドットが付きます（例: .Steve）。
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Bedrock 対応に必要なため、標準（PaperMC）サーバーに切り替えました。
Downloading Geyser and Floodgate (Bedrock support) ...	Geyser と Floodgate（Bedrock 対応）をダウンロード中 ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Bedrock 対応をインストールしました（Geyser + Floodgate、UDP {0}）
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	スマホ、ゲーム機、Windows 10/11 も参加できます
Bedrock players (phones, consoles, Windows 10/11) join with:	Bedrock のプレイヤー（スマホ、ゲーム機、Windows 10/11）は次で参加:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	（Minecraft Bedrock で: プレイ > サーバー > サーバーを追加。名前の先頭にドットが付きます。例: .Steve）
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	ヒント: 先にサーバーを停止してください（そのウィンドウで  stop  と入力）。変更は起動時に読み込まれます。
What do you want to change?	何を変更しますか？
Server icon	サーバーアイコン
Add plugins	プラグインを追加
Add mods	MOD を追加
Remove plugins	プラグインを削除
Remove mods	MOD を削除
Any other server.properties setting	その他の server.properties 設定
Change the Minecraft version (now {0})	Minecraft のバージョンを変更（現在 {0}）
Bedrock players: ON (Geyser + Floodgate)	Bedrock プレイヤー: オン（Geyser + Floodgate）
Bedrock players: off	Bedrock プレイヤー: オフ
Make a backup now	今すぐバックアップを作成
Saved.	保存しました。
All done. Start (or restart) your server to use the changes.	完了しました。変更を使うにはサーバーを起動（または再起動）してください。
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	シード、ワールドタイプ、ワールドフォルダ名の変更は新しいワールドにのみ影響します。今のワールドはそのままです。
Backup saved: {0}	バックアップを保存しました: {0}
Making a backup first ...	まずバックアップを作成中 ...
The backup failed - stopping here so nothing is lost.	バックアップに失敗しました。何も失わないようここで中止します。
Which server do you want to change?	どのサーバーを変更しますか？
Pick another folder ...	別のフォルダを選ぶ ...
Type the folder of your server (the one that contains start-all):	サーバーのフォルダを入力してください（start-all があるフォルダ）:
That folder does not look like a server made by this tool.	そのフォルダはこのツールで作られたサーバーではないようです。
{0} file(s) placed in {1}	{0} 個のファイルを {1} に配置しました
Nothing is installed in this folder yet.	このフォルダにはまだ何もインストールされていません。
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	削除するものにチェックを入れてください（removed フォルダに移動され、削除はされません）
Removed {0}	{0} を削除しました
Fetching version list ...	バージョン一覧を取得中 ...
Could not get the version list (is the internet working?).	バージョン一覧を取得できませんでした（インターネットは使えますか？）。
That is the version you already have.	すでにそのバージョンを使っています。
Change Minecraft from {0} to {1}?	Minecraft を {0} から {1} に変更しますか？
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	ワールドは古いバージョンに戻せないため、先に完全なバックアップを作成します。その後、プラグインや MOD の更新が必要になることがあります。
Now on Minecraft {0}	現在は Minecraft {0} です
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	新しいバージョンでプラグインや MOD が動かなくなったら、このメニューで更新または削除してください。元に戻すには backups フォルダのバックアップを復元します。
This loader has no release for that version.	このローダーにはそのバージョン向けのリリースがありません。
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	Bedrock 対応はオンです。オフにしますか？（Geyser と Floodgate は removed フォルダに移動されます。）
Bedrock support turned off.	Bedrock 対応をオフにしました。
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	ここでの Bedrock 対応には通常の PaperMC サーバーが必要です（Velocity、Fabric、Forge は不可）。
Let Bedrock players (phones, consoles, Windows 10/11) join too?	Bedrock のプレイヤー（スマホ、ゲーム機、Windows 10/11）も参加できるようにしますか？
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Geyser と Floodgate を追加します。PaperMC が必要です。Bedrock の名前の先頭にはドットが付きます（例: .Steve）。UDP ポート {0} を使います。
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	サーバーは Vanilla です。PaperMC に切り替えますか？（同じバージョン、同じワールド）先に完全なバックアップを作成します。
PaperMC has no build for this version.	この PaperMC にはこのバージョン用のビルドがありません。
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock のプレイヤーには UDP ポート {0} に届く必要があります。playit.gg なら  bash mc-setup.sh --tunnel-guide  を実行して Bedrock 用トンネルを追加し、ルーターの場合は UDP {0} も転送してください。
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock のプレイヤーには UDP ポート {0} に届く必要があります。playit.gg なら  powershell -File mc-setup.ps1 -TunnelGuide  を実行して Bedrock 用トンネルを追加し、ルーターの場合は UDP {0} も転送してください。
In my home folder	ホームフォルダ内
EOF
}
lang_data_ko() { cat <<'EOF'
Let's set up your Minecraft server	Minecraft 서버를 설정해 봅시다
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	화살표 키와 Enter를 사용하세요. 언제든 Ctrl+C로 종료할 수 있습니다.
Nothing is installed until you confirm at the end.	마지막에 확인하기 전까지는 아무것도 설치되지 않습니다.
How do you want to set up?	어떻게 설정하시겠습니까?
Simple - a few easy questions, everything else is chosen for you	간단: 쉬운 질문 몇 개, 나머지는 자동 선택
Advanced - choose every option yourself	고급: 모든 옵션을 직접 선택
What do you want to call your server?	서버 이름을 무엇으로 할까요?
Where should your server be saved? A new folder with your server's name is created there.	서버를 어디에 저장할까요? 서버 이름의 새 폴더가 그곳에 만들어집니다.
Next to this script (recommended)	이 스크립트 옆 (권장)
On my Desktop	바탕 화면
In my Documents folder	문서 폴더
Somewhere else (type a folder)	다른 위치 (폴더 입력)
Somewhere else (browse or type a folder)	다른 위치 (찾아보기 또는 폴더 입력)
Your server will be installed in:	서버가 설치될 위치:
Yes, use this folder	예, 이 폴더 사용
No, pick another place	아니요, 다른 위치 선택
Which kind of server do you want?	어떤 종류의 서버를 원하시나요?
Standard (recommended) - fast, and you can add plugins later	표준 (권장): 빠르고 나중에 플러그인 추가 가능
Pure Minecraft - exactly like the official game	순정 마인크래프트: 공식 게임과 동일
How will your friends join?	친구들은 어떻게 접속하나요?
Over the internet - easiest, no router settings (free)	인터넷으로: 가장 쉬움, 공유기 설정 필요 없음 (무료)
Over the internet using my router (port forwarding)	인터넷으로, 내 공유기 사용 (포트 포워딩)
Only people on my home Wi-Fi	우리 집 Wi-Fi에 있는 사람만
Does everyone who will join own Minecraft (a paid Microsoft account)?	접속할 모든 사람이 Minecraft(유료 Microsoft 계정)를 가지고 있나요?
YES = safest, recommended.	예 = 가장 안전, 권장.
NO  = anyone can join with any name (only for friends you trust).	아니요 = 누구나 아무 이름으로 접속 가능 (믿는 친구에게만).
Yes	예
No	아니요
Finding the newest version ...	최신 버전을 찾는 중 ...
Want to change more things (server message, icon, mods, whitelist, world...)?	더 많은 것을 바꾸시겠습니까 (메시지, 아이콘, 모드, 화이트리스트, 월드...)?
Most people choose No - you can still do that later.	대부분 '아니요'를 선택합니다. 나중에도 바꿀 수 있어요.
Minecraft EULA	Minecraft EULA(최종 사용자 사용권 계약)
To run a server you must agree to the Minecraft End User License Agreement:	서버를 실행하려면 Minecraft 최종 사용자 사용권 계약에 동의해야 합니다:
Do you agree to the EULA?	EULA에 동의하십니까?
Summary	요약
Install now?	지금 설치할까요?
Installing your Minecraft server	Minecraft 서버를 설치하는 중
Step 1 of 4 - Checking Java	1/4단계: Java 확인
Step 2 of 4 - Downloading Minecraft (this can take a minute)	2/4단계: Minecraft 다운로드 (1분 정도 걸릴 수 있음)
Step 3 of 4 - Setting up internet access	3/4단계: 인터넷 접속 설정
Step 4 of 4 - Finishing up	4/4단계: 마무리
Your server is ready	서버 준비 완료
To start your server, run:	서버를 시작하려면 다음을 실행하세요:
To stop it, type  stop  in the server window.	중지하려면 서버 창에 stop 을 입력하세요.
Friends join with:	친구들은 이 주소로 접속:
Note: anyone can join with any name. Only share the address with people you trust.	참고: 누구나 아무 이름으로 접속할 수 있습니다. 믿는 사람에게만 주소를 공유하세요.
(Your playit.gg address. Keep playit running while you play.)	(내 playit.gg 주소입니다. 플레이하는 동안 playit를 켜 두세요.)
(Only on the same Wi-Fi.)	(같은 Wi-Fi에서만 가능합니다.)
Start the server now?	지금 서버를 시작할까요?
All set - have fun!	모두 완료! 즐거운 시간 되세요!
Setup cancelled. Nothing was installed.	설정이 취소되었습니다. 아무것도 설치되지 않았습니다.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	단계별 안내로 무료 playit.gg 터널을 지금 설정할까요? (약 10분, 나중에 해도 됩니다)
playit.gg tunnel	playit.gg 터널
Name:	이름:
Type:	종류:
Friends:	친구:
Accounts:	계정:
Memory:	메모리:
Folder:	폴더:
Standard	표준
Pure Minecraft	순정 마인크래프트
over the internet (free tunnel)	인터넷 (무료 터널)
over the internet (router port forwarding)	인터넷 (포트 포워딩)
home Wi-Fi only	집 Wi-Fi만
everyone needs a Minecraft account	모두 Minecraft 계정이 필요
anyone can join with any name	누구나 아무 이름으로 접속 가능
Press Enter to close	Enter를 눌러 닫기
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	이 창에서 이 언어를 표시할 수 있는지 확실하지 않습니다. 선택 후 네모나 ?가 보이면 다시 시작해서 영어를 선택하세요(Microsoft Store의 Windows Terminal이 가장 좋습니다).
Use this language	이 언어 사용
Use English instead	대신 영어 사용
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	이 터미널은 UTF-8이 아니어서 이 언어가 깨져 보일 수 있습니다(네모 또는 ?). 영어로 계속할까요?
Use English	영어 사용
Try it anyway	그래도 시도
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	팁: 글자 대신 네모가 보이면  -Lang en  으로 다시 실행하거나 Windows Terminal을 사용하세요.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	팁: 글자 대신 네모가 보이면  --lang en  으로 다시 실행하거나 해당 글꼴을 지원하는 터미널을 사용하세요.
none	없음
plugins	플러그인
mods	모드
Back	뒤로
Customise your server. Pick a category; choose 'done' when finished.	서버를 설정합니다. 항목을 고르고, 끝나면 '완료'를 선택하세요.
Server name: {0}	서버 이름: {0}
Server list message with colours: {0}	서버 목록 메시지(색상 포함): {0}
Server icon: {0}	서버 아이콘: {0}
Mods: {0} queued	모드: {0}개 대기 중
Plugins: {0} queued	플러그인: {0}개 대기 중
Operators ({0}) and whitelist ({1})	관리자({0}) 및 화이트리스트({1})
World type, seed, structures, nether, hardcore	월드 유형, 시드, 구조물, 네더, 하드코어
PvP, command blocks, flying, mobs, spawn protection	PvP, 명령 블록, 비행, 몹, 스폰 보호
View / simulation distance: {0} / {1}	시야 / 시뮬레이션 거리: {0} / {1}
Resource pack: {0}	리소스 팩: {0}
Any other server.properties setting ({0})	기타 server.properties 설정({0})
Auto-restart on crash, backup script	충돌 시 자동 재시작, 백업 스크립트
Finished customising	설정 완료
Name of your server (e.g. Creeper Cove).	서버 이름 (예: Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	창 제목, 자동 시작 항목, 백업에 사용되며, 따로 설정하지 않으면 서버 목록 메시지로도 쓰입니다.
Server list message (MOTD).	서버 목록 메시지(MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	색상: &0 검정 &1 진한 파랑 &2 진한 초록 &3 진한 청록 &4 진한 빨강 &5 보라 &6 금색
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 회색 &8 진한 회색 &9 파랑 &a 초록 &b 청록 &c 빨강 &d 분홍 &e 노랑 &f 흰색
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	스타일: &l 굵게  &o 기울임  &n 밑줄  &k 흐리게(난독화)  &r 초기화
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	\n 으로 둘째 줄을 만듭니다.    예: &6&lMy Server\n&7Welcome!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	서버 아이콘: 이미지 경로(png/jpg/gif...) 또는 https:// 링크.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	자동으로 64x64 픽셀로 변환됩니다(가운데를 정사각형으로 자름).
Leave empty for no icon.	비워 두면 아이콘이 없습니다.
File not found: {0}	파일을 찾을 수 없음: {0}
Server icon created (64x64)	서버 아이콘을 만들었습니다(64x64)
Checking which popular {0} work with Minecraft {1} ...	Minecraft {1}에서 작동하는 인기 {0}을(를) 확인하는 중 ...
[not updated for {0} yet - newest version will be tried]	[아직 {0}용으로 업데이트되지 않음 - 최신 버전을 시도합니다]
You already added everything in the popular list. Try the search option for more.	인기 목록의 항목을 모두 추가했습니다. 더 찾으려면 검색을 사용하세요.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0}은(는) 매우 최신이라 플러그인 {1}개가 아직 업데이트되지 않은 것으로 표시됩니다. 대개 그래도 작동하니 시도해 보려면 선택하세요.
Pick the {0} you want (Space = tick, Enter = done, A = all)	원하는 {0}을(를) 고르세요 (Space = 선택, Enter = 완료, A = 전체)
Added {0}	{0} 추가됨
Add {0}  ({1} queued, loader: {2})	{0} 추가 ({1}개 대기 중, 로더: {2})
Add {0}  ({1} queued)	{0} 추가 ({1}개 대기 중)
Pick from a list of popular {0}	인기 {0} 목록에서 고르기
Search Modrinth for {0} (compatible with {1})	Modrinth에서 {0} 검색 ({1} 호환)
Add direct https:// links to .jar files	.jar 파일의 직접 https:// 링크 추가
Show / remove queued {0}	대기 중인 {0} 보기 / 제거
Done with {0}	{0} 완료
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Modrinth 검색 (Minecraft {1}용 {0}). 예: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	Modrinth 검색에 실패했습니다.
Nothing found for '{0}' that works with Minecraft {1}.	Minecraft {1}에서 작동하는 '{0}' 결과가 없습니다.
Results for '{0}':	'{0}' 검색 결과:
Added '{0}' (and any required dependencies).	'{0}'을(를) 추가했습니다(필요한 종속성 포함).
Direct https:// links to .jar files, separated by spaces.	.jar 파일의 직접 https:// 링크를 공백으로 구분해 입력하세요.
Only use links from sources you trust - these files run on your server.	신뢰할 수 있는 출처의 링크만 사용하세요. 이 파일들은 서버에서 실행됩니다.
Skipping '{0}' (must start with https://)	'{0}' 건너뜀 (https://로 시작해야 함)
Nothing queued yet.	아직 대기 중인 항목이 없습니다.
Back (keep everything)	뒤로 (모두 유지)
Pick one to REMOVE from the install list:	설치 목록에서 제거할 항목을 고르세요:
Skipping invalid name '{0}'	잘못된 이름 '{0}' 건너뜀
Operators (admins). Minecraft usernames separated by spaces or commas.	관리자(OP). Minecraft 사용자 이름을 공백이나 쉼표로 구분하세요.
Ops can use all commands.	관리자는 모든 명령어를 사용할 수 있습니다.
Whitelist: only these players may join. Usernames separated by spaces or commas.	화이트리스트: 이 플레이어만 접속할 수 있습니다. 사용자 이름을 공백이나 쉼표로 구분하세요.
Leave empty to keep the whitelist as chosen earlier.	비워 두면 앞서 선택한 화이트리스트를 유지합니다.
Could not look up '{0}' - add later with: whitelist add {0}	'{0}'을(를) 찾지 못했습니다. 나중에 추가: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	'{0}'을(를) 찾지 못했습니다. 나중에 추가: op {0}
World type:	월드 유형:
Normal terrain	일반 지형
Superflat	슈퍼플랫
Large biomes	큰 생물 군계
Amplified (tall mountains)	증폭됨 (높은 산)
World seed (empty = random):	월드 시드 (비우면 무작위):
World folder name:	월드 폴더 이름:
Generate structures (villages, strongholds, ...)?	구조물(마을, 요새 등)을 생성할까요?
Allow the Nether?	네더를 허용할까요?
Hardcore mode? (one life, forced hard difficulty)	하드코어 모드? (목숨 1개, 어려움 난이도 강제)
Allow player-vs-player combat (PvP)?	플레이어 간 전투(PvP)를 허용할까요?
Enable command blocks?	명령 블록을 켤까요?
Allow flying (needed for some mods; otherwise flight is kicked)?	비행을 허용할까요? (일부 모드에 필요하며, 아니면 비행 시 추방됩니다)
Spawn animals?	동물을 생성할까요?
Spawn monsters?	몬스터를 생성할까요?
Spawn villagers?	주민을 생성할까요?
Force everyone into the default game mode on every join?	접속할 때마다 모두를 기본 게임 모드로 강제할까요?
Spawn protection radius in blocks (0 = off):	스폰 보호 반경(블록 단위, 0 = 끔):
Kick idle players after N minutes (0 = never):	N분 동안 활동이 없는 플레이어 추방 (0 = 안 함):
View distance in chunks (2-32). Lower = faster:	시야 거리(청크, 2-32). 낮을수록 빠름:
Simulation distance in chunks (2-32). Lower = faster:	시뮬레이션 거리(청크, 2-32). 낮을수록 빠름:
Please enter a number from {0} to {1}. Kept: {2}	{0}~{1} 사이의 숫자를 입력하세요. 유지됨: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	서버 리소스 팩: .zip 파일의 직접 https:// 링크 (비우면 없음).
Players are offered it when they join. Its checksum is calculated at install time.	플레이어가 접속할 때 제안됩니다. 체크섬은 설치 시 계산됩니다.
That is not a link. Kept: {0}	링크가 아닙니다. 유지됨: {0}
Kick players who decline the resource pack?	리소스 팩을 거부한 플레이어를 추방할까요?
Any other server.properties setting as key=value, separated by spaces.	그 밖의 server.properties 설정을 키=값 형식으로 공백으로 구분해 입력하세요.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	예: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	'{0}' 건너뜀 (키=값 형식 사용)
Restart the server automatically if it crashes?	서버가 충돌하면 자동으로 다시 시작할까요?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	백업 스크립트를 만들까요? (월드를 backups 폴더에 압축하고 최신 10개 유지)
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	여기서는 모드 로더를 Velocity 구성과 함께 쓸 수 없습니다. (Paper 플러그인은 가능하니 PaperMC를 선택하세요.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	바닐라는 자체적으로 모드를 지원하지 않습니다. 모드 로더를 고르세요(일반 바닐라 서버를 대체합니다):
Fabric - lightweight, huge mod library (recommended)	Fabric - 가볍고 모드가 매우 많음 (권장)
NeoForge - big content mods (1.20.2+)	NeoForge - 대형 콘텐츠 모드 (1.20.2+)
Forge - classic loader (1.17+)	Forge - 클래식 로더 (1.17+)
Plain Vanilla, no mods	순수 바닐라, 모드 없음
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0}은(는) Minecraft {1}용 서버 릴리스가 없습니다. 다른 로더나 다른 Minecraft 버전을 고르세요.
Modrinth lookup failed for '{0}'.	Modrinth에서 '{0}' 조회에 실패했습니다.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	'{0}'은(는) 아직 {1}용으로 표시되지 않았지만 최신 버전({2})을 추가했습니다. 그래도 작동할 수 있습니다.
'{0}' has no download for {1} on this loader.	'{0}'은(는) 이 로더에서 {1}용 다운로드가 없습니다.
Newest (recommended)	최신 (권장)
Type a specific older version	특정 이전 버전 직접 입력
Which Minecraft version? (newest first)	어떤 Minecraft 버전을 쓸까요? (최신순)
Type the exact Minecraft version (e.g. 1.20.1):	정확한 Minecraft 버전을 입력하세요 (예: 1.20.1):
That version is not available. Pick one from the list instead.	해당 버전은 사용할 수 없습니다. 목록에서 선택하세요.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	Bedrock 플레이어(휴대폰, 콘솔, Windows 10/11)도 접속할 수 있게 할까요?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	무료 애드온인 Geyser를 통해 접속하므로 Java 계정이 필요 없습니다. 표준(Paper) 서버가 필요하며 자동으로 선택됩니다. Bedrock 이름 앞에는 점이 붙습니다(예: .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	Bedrock 플레이어도 접속할 수 있게 할까요? (Geyser + Floodgate)
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Bedrock Edition 플레이어(휴대폰, 콘솔, Windows 10/11)가 Java 계정 없이 접속할 수 있습니다. PaperMC가 필요하며 UDP 포트 19132를 엽니다. Bedrock 플레이어 이름 앞에는 점이 붙습니다(예: .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Bedrock 지원에 필요하므로 표준(PaperMC) 서버로 전환했습니다.
Downloading Geyser and Floodgate (Bedrock support) ...	Geyser와 Floodgate(Bedrock 지원) 다운로드 중 ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Bedrock 지원 설치됨 (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	휴대폰, 콘솔, Windows 10/11도 접속할 수 있음
Bedrock players (phones, consoles, Windows 10/11) join with:	Bedrock 플레이어(휴대폰, 콘솔, Windows 10/11)는 다음으로 접속:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(Minecraft Bedrock에서: 플레이 > 서버 > 서버 추가. 이름 앞에 점이 붙습니다. 예: .Steve)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	팁: 먼저 서버를 중지하세요(서버 창에  stop  입력). 변경 사항은 시작할 때 적용됩니다.
What do you want to change?	무엇을 바꿀까요?
Server icon	서버 아이콘
Add plugins	플러그인 추가
Add mods	모드 추가
Remove plugins	플러그인 제거
Remove mods	모드 제거
Any other server.properties setting	기타 server.properties 설정
Change the Minecraft version (now {0})	Minecraft 버전 변경 (현재 {0})
Bedrock players: ON (Geyser + Floodgate)	Bedrock 플레이어: 켜짐 (Geyser + Floodgate)
Bedrock players: off	Bedrock 플레이어: 꺼짐
Make a backup now	지금 백업 만들기
Saved.	저장됨.
All done. Start (or restart) your server to use the changes.	모두 완료되었습니다. 변경 사항을 쓰려면 서버를 시작(또는 재시작)하세요.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	시드, 월드 유형, 월드 폴더 이름을 바꿔도 새 월드에만 적용됩니다. 현재 월드는 그대로 유지됩니다.
Backup saved: {0}	백업 저장됨: {0}
Making a backup first ...	먼저 백업을 만드는 중 ...
The backup failed - stopping here so nothing is lost.	백업에 실패했습니다. 아무것도 잃지 않도록 여기서 멈춥니다.
Which server do you want to change?	어느 서버를 바꿀까요?
Pick another folder ...	다른 폴더 선택 ...
Type the folder of your server (the one that contains start-all):	서버 폴더를 입력하세요 (start-all이 들어 있는 폴더):
That folder does not look like a server made by this tool.	이 폴더는 이 도구로 만든 서버처럼 보이지 않습니다.
{0} file(s) placed in {1}	{0}개 파일을 {1}에 넣었습니다
Nothing is installed in this folder yet.	이 폴더에는 아직 설치된 것이 없습니다.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	제거할 항목을 선택하세요 (삭제되지 않고 removed 폴더로 이동됩니다)
Removed {0}	{0} 제거됨
Fetching version list ...	버전 목록을 가져오는 중 ...
Could not get the version list (is the internet working?).	버전 목록을 가져오지 못했습니다 (인터넷이 연결되어 있나요?).
That is the version you already have.	이미 사용 중인 버전입니다.
Change Minecraft from {0} to {1}?	Minecraft를 {0}에서 {1}(으)로 바꿀까요?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	월드는 이전 버전으로 되돌릴 수 없으므로 먼저 전체 백업을 만듭니다. 이후 플러그인과 모드를 업데이트해야 할 수 있습니다.
Now on Minecraft {0}	이제 Minecraft {0}입니다
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	새 버전에서 플러그인이나 모드가 작동하지 않으면 이 메뉴에서 업데이트하거나 제거하세요. 되돌리려면 backups 폴더의 백업을 복원하세요.
This loader has no release for that version.	이 로더에는 해당 버전용 릴리스가 없습니다.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	Bedrock 지원이 켜져 있습니다. 끌까요? (Geyser와 Floodgate는 removed 폴더로 이동됩니다.)
Bedrock support turned off.	Bedrock 지원을 껐습니다.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	여기서 Bedrock 지원은 일반 PaperMC 서버가 필요합니다 (Velocity, Fabric, Forge는 불가).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	Bedrock 플레이어(휴대폰, 콘솔, Windows 10/11)도 접속할 수 있게 할까요?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Geyser와 Floodgate가 추가됩니다. PaperMC가 필요합니다. Bedrock 이름 앞에는 점이 붙습니다(예: .Steve). UDP 포트 {0}을(를) 사용합니다.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	서버가 바닐라입니다. PaperMC로 전환할까요? (같은 버전, 같은 월드) 먼저 전체 백업을 만듭니다.
PaperMC has no build for this version.	PaperMC에는 이 버전용 빌드가 없습니다.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock 플레이어는 UDP 포트 {0}에 접근할 수 있어야 합니다. playit.gg는  bash mc-setup.sh --tunnel-guide  를 실행해 Bedrock 터널을 추가하고, 공유기는 UDP {0}도 포워딩하세요.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock 플레이어는 UDP 포트 {0}에 접근할 수 있어야 합니다. playit.gg는  powershell -File mc-setup.ps1 -TunnelGuide  를 실행해 Bedrock 터널을 추가하고, 공유기는 UDP {0}도 포워딩하세요.
In my home folder	내 홈 폴더
EOF
}
lang_data_hi() { cat <<'EOF'
Let's set up your Minecraft server	आइए आपका Minecraft सर्वर सेट करें
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	तीर कुंजियों और Enter का उपयोग करें। कभी भी बाहर निकलने के लिए Ctrl+C दबाएँ।
Nothing is installed until you confirm at the end.	अंत में पुष्टि करने तक कुछ भी इंस्टॉल नहीं होगा।
How do you want to set up?	आप सेटअप कैसे करना चाहते हैं?
Simple - a few easy questions, everything else is chosen for you	सरल: कुछ आसान सवाल, बाकी सब अपने आप चुना जाएगा
Advanced - choose every option yourself	उन्नत: हर विकल्प खुद चुनें
What do you want to call your server?	आप अपने सर्वर का नाम क्या रखना चाहते हैं?
Where should your server be saved? A new folder with your server's name is created there.	आपका सर्वर कहाँ सहेजा जाए? वहाँ सर्वर के नाम का नया फ़ोल्डर बनेगा।
Next to this script (recommended)	इस स्क्रिप्ट के पास (अनुशंसित)
On my Desktop	मेरे डेस्कटॉप पर
In my Documents folder	मेरे दस्तावेज़ फ़ोल्डर में
Somewhere else (type a folder)	कहीं और (फ़ोल्डर टाइप करें)
Somewhere else (browse or type a folder)	कहीं और (ब्राउज़ करें या फ़ोल्डर टाइप करें)
Your server will be installed in:	आपका सर्वर यहाँ इंस्टॉल होगा:
Yes, use this folder	हाँ, यही फ़ोल्डर इस्तेमाल करें
No, pick another place	नहीं, कोई और जगह चुनें
Which kind of server do you want?	आपको किस प्रकार का सर्वर चाहिए?
Standard (recommended) - fast, and you can add plugins later	मानक (अनुशंसित): तेज़, और प्लगइन बाद में जोड़ सकते हैं
Pure Minecraft - exactly like the official game	शुद्ध Minecraft: बिल्कुल आधिकारिक गेम जैसा
How will your friends join?	आपके दोस्त कैसे जुड़ेंगे?
Over the internet - easiest, no router settings (free)	इंटरनेट से: सबसे आसान, राउटर सेटिंग नहीं (मुफ़्त)
Over the internet using my router (port forwarding)	इंटरनेट से, मेरे राउटर के ज़रिए (पोर्ट फ़ॉरवर्डिंग)
Only people on my home Wi-Fi	सिर्फ़ मेरे घर के Wi-Fi पर मौजूद लोग
Does everyone who will join own Minecraft (a paid Microsoft account)?	क्या शामिल होने वाले सभी के पास Minecraft (सशुल्क Microsoft खाता) है?
YES = safest, recommended.	हाँ = सबसे सुरक्षित, अनुशंसित।
NO  = anyone can join with any name (only for friends you trust).	नहीं = कोई भी किसी भी नाम से जुड़ सकता है (केवल भरोसेमंद दोस्तों के लिए)।
Yes	हाँ
No	नहीं
Finding the newest version ...	नवीनतम संस्करण खोजा जा रहा है ...
Want to change more things (server message, icon, mods, whitelist, world...)?	क्या और चीज़ें बदलना चाहते हैं (संदेश, आइकन, मॉड, व्हाइटलिस्ट, दुनिया...)?
Most people choose No - you can still do that later.	ज़्यादातर लोग 'नहीं' चुनते हैं; आप यह बाद में भी कर सकते हैं।
Minecraft EULA	Minecraft EULA (उपयोगकर्ता लाइसेंस समझौता)
To run a server you must agree to the Minecraft End User License Agreement:	सर्वर चलाने के लिए आपको Minecraft के उपयोगकर्ता लाइसेंस समझौते से सहमत होना होगा:
Do you agree to the EULA?	क्या आप EULA से सहमत हैं?
Summary	सारांश
Install now?	अभी इंस्टॉल करें?
Installing your Minecraft server	आपका Minecraft सर्वर इंस्टॉल हो रहा है
Step 1 of 4 - Checking Java	चरण 1/4: Java जाँचना
Step 2 of 4 - Downloading Minecraft (this can take a minute)	चरण 2/4: Minecraft डाउनलोड हो रहा है (एक मिनट लग सकता है)
Step 3 of 4 - Setting up internet access	चरण 3/4: इंटरनेट एक्सेस सेट करना
Step 4 of 4 - Finishing up	चरण 4/4: समापन
Your server is ready	आपका सर्वर तैयार है
To start your server, run:	सर्वर शुरू करने के लिए यह चलाएँ:
To stop it, type  stop  in the server window.	रोकने के लिए सर्वर विंडो में  stop  टाइप करें।
Friends join with:	दोस्त इससे जुड़ेंगे:
Note: anyone can join with any name. Only share the address with people you trust.	ध्यान दें: कोई भी किसी भी नाम से जुड़ सकता है। पता केवल भरोसेमंद लोगों को दें।
(Your playit.gg address. Keep playit running while you play.)	(आपका playit.gg पता। खेलते समय playit चालू रखें।)
(Only on the same Wi-Fi.)	(केवल उसी Wi-Fi पर।)
Start the server now?	क्या सर्वर अभी शुरू करें?
All set - have fun!	सब तैयार, मज़े करें!
Setup cancelled. Nothing was installed.	सेटअप रद्द किया गया। कुछ भी इंस्टॉल नहीं हुआ।
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	क्या चरण-दर-चरण गाइड से अभी मुफ़्त playit.gg टनल सेट करें? (लगभग 10 मिनट, बाद में भी कर सकते हैं)
playit.gg tunnel	playit.gg टनल
Name:	नाम:
Type:	प्रकार:
Friends:	दोस्त:
Accounts:	खाते:
Memory:	मेमोरी:
Folder:	फ़ोल्डर:
Standard	मानक
Pure Minecraft	शुद्ध Minecraft
over the internet (free tunnel)	इंटरनेट से (मुफ़्त टनल)
over the internet (router port forwarding)	इंटरनेट से (पोर्ट फ़ॉरवर्डिंग)
home Wi-Fi only	केवल घर का Wi-Fi
everyone needs a Minecraft account	सभी को Minecraft खाता चाहिए
anyone can join with any name	कोई भी किसी भी नाम से जुड़ सकता है
Press Enter to close	बंद करने के लिए Enter दबाएँ
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	पक्का नहीं है कि यह विंडो इस भाषा को दिखा पाएगी। चुनने के बाद अगर आपको चौकोर या ? दिखें, तो दोबारा शुरू करके अंग्रेज़ी चुनें (Microsoft Store का Windows Terminal सबसे अच्छा चलता है)।
Use this language	यही भाषा इस्तेमाल करें
Use English instead	इसके बजाय अंग्रेज़ी इस्तेमाल करें
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	यह टर्मिनल UTF-8 पर सेट नहीं है, इसलिए यह भाषा गड़बड़ दिख सकती है (चौकोर या ?)। अंग्रेज़ी में जारी रखें?
Use English	अंग्रेज़ी इस्तेमाल करें
Try it anyway	फिर भी आज़माएँ
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	सुझाव: अगर अक्षरों की जगह चौकोर दिखें, तो  -Lang en  के साथ दोबारा चलाएँ या Windows Terminal इस्तेमाल करें।
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	सुझाव: अगर अक्षरों की जगह चौकोर दिखें, तो  --lang en  के साथ दोबारा चलाएँ या सही फ़ॉन्ट वाला टर्मिनल इस्तेमाल करें।
none	कोई नहीं
plugins	प्लगइन
mods	मॉड
Back	वापस
Customise your server. Pick a category; choose 'done' when finished.	अपने सर्वर को कस्टमाइज़ करें। एक श्रेणी चुनें; पूरा होने पर 'पूर्ण' चुनें।
Server name: {0}	सर्वर का नाम: {0}
Server list message with colours: {0}	रंगों के साथ सर्वर सूची संदेश: {0}
Server icon: {0}	सर्वर आइकन: {0}
Mods: {0} queued	मॉड: {0} कतार में
Plugins: {0} queued	प्लगइन: {0} कतार में
Operators ({0}) and whitelist ({1})	ऑपरेटर ({0}) और व्हाइटलिस्ट ({1})
World type, seed, structures, nether, hardcore	दुनिया का प्रकार, सीड, संरचनाएँ, नेदर, हार्डकोर
PvP, command blocks, flying, mobs, spawn protection	PvP, कमांड ब्लॉक, उड़ान, मॉब, स्पॉन सुरक्षा
View / simulation distance: {0} / {1}	दृश्य / सिमुलेशन दूरी: {0} / {1}
Resource pack: {0}	रिसोर्स पैक: {0}
Any other server.properties setting ({0})	कोई अन्य server.properties सेटिंग ({0})
Auto-restart on crash, backup script	क्रैश पर ऑटो-रीस्टार्ट, बैकअप स्क्रिप्ट
Finished customising	कस्टमाइज़ करना समाप्त करें
Name of your server (e.g. Creeper Cove).	आपके सर्वर का नाम (जैसे Creeper Cove)।
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	विंडो शीर्षक, ऑटोस्टार्ट एंट्री, बैकअप में उपयोग होता है, और यदि आपने खुद कोई संदेश नहीं रखा तो सर्वर सूची में संदेश के रूप में भी।
Server list message (MOTD).	सर्वर सूची संदेश (MOTD)।
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	रंग: &0 काला &1 गहरा नीला &2 गहरा हरा &3 गहरा फ़िरोज़ी &4 गहरा लाल &5 बैंगनी &6 सुनहरा
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 धूसर &8 गहरा धूसर &9 नीला &a हरा &b फ़िरोज़ी &c लाल &d गुलाबी &e पीला &f सफ़ेद
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	शैलियाँ: &l बोल्ड  &o इटैलिक  &n रेखांकित  &k गड़बड़  &r रीसेट
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	दूसरी पंक्ति के लिए \n का उपयोग करें।    उदाहरण: &6&lMy Server\n&7Welcome!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	सर्वर आइकन: किसी चित्र का पथ (png/jpg/gif...) या https:// लिंक।
It is converted to 64x64 pixels automatically (centre-cropped to a square).	यह अपने-आप 64x64 पिक्सेल में बदल जाता है (बीच से वर्गाकार कटता है)।
Leave empty for no icon.	आइकन न चाहिए तो खाली छोड़ें।
File not found: {0}	फ़ाइल नहीं मिली: {0}
Server icon created (64x64)	सर्वर आइकन बन गया (64x64)
Checking which popular {0} work with Minecraft {1} ...	जाँच रहे हैं कि कौन-से लोकप्रिय {0} Minecraft {1} के साथ काम करते हैं ...
[not updated for {0} yet - newest version will be tried]	[अभी {0} के लिए अपडेट नहीं - नवीनतम संस्करण आज़माया जाएगा]
You already added everything in the popular list. Try the search option for more.	आप लोकप्रिय सूची की सभी चीज़ें जोड़ चुके हैं। और के लिए खोज आज़माएँ।
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} बहुत नया है, इसलिए {1} प्लगइन अभी अपडेट नहीं के रूप में चिह्नित हैं। वे अक्सर फिर भी काम करते हैं; आज़माना चाहें तो चुनें।
Pick the {0} you want (Space = tick, Enter = done, A = all)	अपने मनचाहे {0} चुनें (Space = टिक, Enter = पूर्ण, A = सभी)
Added {0}	{0} जोड़ा गया
Add {0}  ({1} queued, loader: {2})	{0} जोड़ें  ({1} कतार में, लोडर: {2})
Add {0}  ({1} queued)	{0} जोड़ें  ({1} कतार में)
Pick from a list of popular {0}	लोकप्रिय {0} की सूची से चुनें
Search Modrinth for {0} (compatible with {1})	Modrinth पर {0} खोजें ({1} के साथ संगत)
Add direct https:// links to .jar files	.jar फ़ाइलों के सीधे https:// लिंक जोड़ें
Show / remove queued {0}	कतार वाले {0} देखें / हटाएँ
Done with {0}	{0} पूर्ण
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Modrinth खोजें (Minecraft {1} के लिए {0})। उदाहरण: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	Modrinth खोज विफल रही।
Nothing found for '{0}' that works with Minecraft {1}.	'{0}' के लिए Minecraft {1} के साथ काम करने वाला कुछ नहीं मिला।
Results for '{0}':	'{0}' के परिणाम:
Added '{0}' (and any required dependencies).	'{0}' जोड़ा गया (और सभी आवश्यक निर्भरताएँ)।
Direct https:// links to .jar files, separated by spaces.	.jar फ़ाइलों के सीधे https:// लिंक, स्पेस से अलग करके।
Only use links from sources you trust - these files run on your server.	केवल भरोसेमंद स्रोतों के लिंक उपयोग करें - ये फ़ाइलें आपके सर्वर पर चलती हैं।
Skipping '{0}' (must start with https://)	'{0}' छोड़ा गया (https:// से शुरू होना चाहिए)
Nothing queued yet.	अभी कतार में कुछ नहीं है।
Back (keep everything)	वापस (सब कुछ रखें)
Pick one to REMOVE from the install list:	इंस्टॉल सूची से हटाने के लिए एक चुनें:
Skipping invalid name '{0}'	अमान्य नाम '{0}' छोड़ा गया
Operators (admins). Minecraft usernames separated by spaces or commas.	ऑपरेटर (एडमिन)। Minecraft यूज़रनेम, स्पेस या कॉमा से अलग करके।
Ops can use all commands.	ऑपरेटर सभी कमांड इस्तेमाल कर सकते हैं।
Whitelist: only these players may join. Usernames separated by spaces or commas.	व्हाइटलिस्ट: केवल ये खिलाड़ी जुड़ सकते हैं। यूज़रनेम, स्पेस या कॉमा से अलग करके।
Leave empty to keep the whitelist as chosen earlier.	पहले चुनी गई व्हाइटलिस्ट रखने के लिए खाली छोड़ें।
Could not look up '{0}' - add later with: whitelist add {0}	'{0}' नहीं मिला - बाद में जोड़ें: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	'{0}' नहीं मिला - बाद में जोड़ें: op {0}
World type:	दुनिया का प्रकार:
Normal terrain	सामान्य भूभाग
Superflat	सुपरफ़्लैट
Large biomes	बड़े बायोम
Amplified (tall mountains)	एम्प्लीफ़ाइड (ऊँचे पहाड़)
World seed (empty = random):	वर्ल्ड सीड (खाली = रैंडम):
World folder name:	वर्ल्ड फ़ोल्डर का नाम:
Generate structures (villages, strongholds, ...)?	संरचनाएँ बनाएँ (गाँव, किले, ...)?
Allow the Nether?	नेदर की अनुमति दें?
Hardcore mode? (one life, forced hard difficulty)	हार्डकोर मोड? (एक ही जान, कठिन स्तर अनिवार्य)
Allow player-vs-player combat (PvP)?	खिलाड़ी बनाम खिलाड़ी लड़ाई (PvP) की अनुमति दें?
Enable command blocks?	कमांड ब्लॉक चालू करें?
Allow flying (needed for some mods; otherwise flight is kicked)?	उड़ने की अनुमति दें? (कुछ मॉड के लिए ज़रूरी; वरना उड़ने पर किक हो जाता है)
Spawn animals?	जानवर पैदा हों?
Spawn monsters?	राक्षस पैदा हों?
Spawn villagers?	ग्रामीण पैदा हों?
Force everyone into the default game mode on every join?	हर बार जुड़ने पर सभी को डिफ़ॉल्ट गेम मोड में रखें?
Spawn protection radius in blocks (0 = off):	स्पॉन सुरक्षा की त्रिज्या ब्लॉक में (0 = बंद):
Kick idle players after N minutes (0 = never):	N मिनट निष्क्रिय रहने पर खिलाड़ी को किक करें (0 = कभी नहीं):
View distance in chunks (2-32). Lower = faster:	दृश्य दूरी चंक में (2-32)। कम = तेज़:
Simulation distance in chunks (2-32). Lower = faster:	सिमुलेशन दूरी चंक में (2-32)। कम = तेज़:
Please enter a number from {0} to {1}. Kept: {2}	{0} से {1} के बीच की संख्या दर्ज करें। रखा गया: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	सर्वर रिसोर्स पैक: .zip का सीधा https:// लिंक (खाली = कोई नहीं)।
Players are offered it when they join. Its checksum is calculated at install time.	खिलाड़ियों के जुड़ते समय यह सुझाया जाता है। इसका चेकसम इंस्टॉल के समय निकाला जाता है।
That is not a link. Kept: {0}	यह लिंक नहीं है। रखा गया: {0}
Kick players who decline the resource pack?	रिसोर्स पैक अस्वीकार करने वाले खिलाड़ियों को किक करें?
Any other server.properties setting as key=value, separated by spaces.	कोई अन्य server.properties सेटिंग कुंजी=मान रूप में, स्पेस से अलग करके।
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	उदाहरण: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	'{0}' छोड़ा गया (कुंजी=मान का उपयोग करें)
Restart the server automatically if it crashes?	क्रैश होने पर सर्वर अपने-आप रीस्टार्ट करें?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	बैकअप स्क्रिप्ट बनाएँ? (वर्ल्ड को backups फ़ोल्डर में ज़िप करती है, नवीनतम 10 रखती है)
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	मॉड लोडर को यहाँ Velocity सेटअप के साथ नहीं जोड़ा जा सकता। (Paper प्लगइन चल सकते हैं - PaperMC चुनें।)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla में मॉड का अपना समर्थन नहीं है। एक मॉड लोडर चुनें (यह सादे Vanilla सर्वर की जगह लेता है):
Fabric - lightweight, huge mod library (recommended)	Fabric - हल्का, मॉड की विशाल लाइब्रेरी (अनुशंसित)
NeoForge - big content mods (1.20.2+)	NeoForge - बड़े कंटेंट मॉड (1.20.2+)
Forge - classic loader (1.17+)	Forge - क्लासिक लोडर (1.17+)
Plain Vanilla, no mods	सादा Vanilla, कोई मॉड नहीं
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} का Minecraft {1} के लिए कोई सर्वर रिलीज़ नहीं है। कोई और लोडर या दूसरा Minecraft संस्करण चुनें।
Modrinth lookup failed for '{0}'.	Modrinth पर '{0}' की खोज विफल रही।
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	'{0}' अभी {1} के लिए चिह्नित नहीं है - इसका नवीनतम संस्करण ({2}) जोड़ा गया। यह फिर भी काम कर सकता है।
'{0}' has no download for {1} on this loader.	'{0}' का इस लोडर पर {1} के लिए कोई डाउनलोड नहीं है।
Newest (recommended)	नवीनतम (अनुशंसित)
Type a specific older version	कोई विशेष पुराना संस्करण टाइप करें
Which Minecraft version? (newest first)	कौन-सा Minecraft संस्करण? (नवीनतम पहले)
Type the exact Minecraft version (e.g. 1.20.1):	सटीक Minecraft संस्करण टाइप करें (जैसे 1.20.1):
That version is not available. Pick one from the list instead.	वह संस्करण उपलब्ध नहीं है। सूची से चुनें।
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	क्या Bedrock खिलाड़ी (फ़ोन, कंसोल, Windows 10/11) भी जुड़ सकें?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	वे Geyser नाम के मुफ़्त ऐड-ऑन से जुड़ते हैं, इसलिए उन्हें Java खाते की ज़रूरत नहीं। इसके लिए मानक (Paper) सर्वर चाहिए, जो आपके लिए चुन लिया जाता है। Bedrock नामों के आगे एक बिंदु लगता है (जैसे .Steve)।
Also let Bedrock players join (Geyser + Floodgate)?	क्या Bedrock खिलाड़ी भी जुड़ सकें (Geyser + Floodgate)?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Bedrock Edition के खिलाड़ी (फ़ोन, कंसोल, Windows 10/11) तब Java खाते के बिना जुड़ सकते हैं। इसके लिए PaperMC चाहिए और UDP पोर्ट 19132 खुलता है। Bedrock खिलाड़ियों के नामों के आगे एक बिंदु लगता है (जैसे .Steve)।
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Bedrock समर्थन के लिए ज़रूरी होने से मानक (PaperMC) सर्वर पर स्विच किया गया।
Downloading Geyser and Floodgate (Bedrock support) ...	Geyser और Floodgate (Bedrock समर्थन) डाउनलोड हो रहे हैं ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Bedrock समर्थन इंस्टॉल हुआ (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	फ़ोन, कंसोल और Windows 10/11 भी जुड़ सकते हैं
Bedrock players (phones, consoles, Windows 10/11) join with:	Bedrock खिलाड़ी (फ़ोन, कंसोल, Windows 10/11) इससे जुड़ते हैं:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(Minecraft Bedrock में: Play > Servers > Add Server। उनके नामों के आगे बिंदु लगता है, जैसे .Steve।)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	सुझाव: पहले सर्वर रोकें (उसकी विंडो में  stop  टाइप करें)। बदलाव शुरू होने पर पढ़े जाते हैं।
What do you want to change?	आप क्या बदलना चाहते हैं?
Server icon	सर्वर आइकन
Add plugins	प्लगइन जोड़ें
Add mods	मॉड जोड़ें
Remove plugins	प्लगइन हटाएँ
Remove mods	मॉड हटाएँ
Any other server.properties setting	कोई अन्य server.properties सेटिंग
Change the Minecraft version (now {0})	Minecraft संस्करण बदलें (अभी {0})
Bedrock players: ON (Geyser + Floodgate)	Bedrock खिलाड़ी: चालू (Geyser + Floodgate)
Bedrock players: off	Bedrock खिलाड़ी: बंद
Make a backup now	अभी बैकअप बनाएँ
Saved.	सहेजा गया।
All done. Start (or restart) your server to use the changes.	सब हो गया। बदलाव इस्तेमाल करने के लिए सर्वर शुरू (या रीस्टार्ट) करें।
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	सीड, वर्ल्ड प्रकार या वर्ल्ड फ़ोल्डर का नाम बदलने का असर केवल नई दुनिया पर होता है। आपकी मौजूदा दुनिया जैसी है वैसी रहती है।
Backup saved: {0}	बैकअप सहेजा गया: {0}
Making a backup first ...	पहले बैकअप बनाया जा रहा है ...
The backup failed - stopping here so nothing is lost.	बैकअप विफल रहा - कुछ खोए बिना यहीं रुक रहे हैं।
Which server do you want to change?	आप कौन-सा सर्वर बदलना चाहते हैं?
Pick another folder ...	कोई और फ़ोल्डर चुनें ...
Type the folder of your server (the one that contains start-all):	अपने सर्वर का फ़ोल्डर टाइप करें (जिसमें start-all है):
That folder does not look like a server made by this tool.	यह फ़ोल्डर इस टूल से बने सर्वर जैसा नहीं लगता।
{0} file(s) placed in {1}	{0} फ़ाइल {1} में रखी गईं
Nothing is installed in this folder yet.	इस फ़ोल्डर में अभी कुछ इंस्टॉल नहीं है।
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	जिन्हें हटाना है उन्हें टिक करें (वे removed नाम के फ़ोल्डर में चले जाते हैं, मिटते नहीं)
Removed {0}	{0} हटाया गया
Fetching version list ...	संस्करण सूची लाई जा रही है ...
Could not get the version list (is the internet working?).	संस्करण सूची नहीं मिल सकी (क्या इंटरनेट चल रहा है?)।
That is the version you already have.	यह वही संस्करण है जो आपके पास पहले से है।
Change Minecraft from {0} to {1}?	Minecraft को {0} से {1} में बदलें?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	दुनियाएँ पुराने संस्करण पर वापस नहीं जा सकतीं, इसलिए पहले पूरा बैकअप बनता है। बाद में प्लगइन और मॉड अपडेट करने पड़ सकते हैं।
Now on Minecraft {0}	अब Minecraft {0} पर
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	यदि कोई प्लगइन या मॉड नए संस्करण में काम करना बंद कर दे, तो इस मेनू से उसे अपडेट या हटाएँ। वापस जाने के लिए backups फ़ोल्डर का बैकअप बहाल करें।
This loader has no release for that version.	इस लोडर का उस संस्करण के लिए कोई रिलीज़ नहीं है।
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	Bedrock समर्थन चालू है। बंद करें? (Geyser और Floodgate removed नाम के फ़ोल्डर में चले जाते हैं।)
Bedrock support turned off.	Bedrock समर्थन बंद किया गया।
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	यहाँ Bedrock समर्थन के लिए सादा PaperMC सर्वर चाहिए (Velocity, Fabric या Forge नहीं)।
Let Bedrock players (phones, consoles, Windows 10/11) join too?	क्या Bedrock खिलाड़ी (फ़ोन, कंसोल, Windows 10/11) भी जुड़ सकें?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Geyser और Floodgate जोड़े जाते हैं। इन्हें PaperMC चाहिए। Bedrock नामों के आगे बिंदु लगता है (जैसे .Steve)। UDP पोर्ट {0} इस्तेमाल होता है।
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	आपका सर्वर Vanilla है। इसे PaperMC पर स्विच करें (वही संस्करण, वही दुनिया)? पहले पूरा बैकअप बनता है।
PaperMC has no build for this version.	PaperMC के पास इस संस्करण के लिए कोई बिल्ड नहीं है।
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock खिलाड़ियों को UDP पोर्ट {0} पहुँच में चाहिए। playit.gg के साथ  bash mc-setup.sh --tunnel-guide  चलाकर Bedrock टनल जोड़ें; राउटर पर UDP {0} भी फ़ॉरवर्ड करें।
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock खिलाड़ियों को UDP पोर्ट {0} पहुँच में चाहिए। playit.gg के साथ  powershell -File mc-setup.ps1 -TunnelGuide  चलाकर Bedrock टनल जोड़ें; राउटर पर UDP {0} भी फ़ॉरवर्ड करें।
In my home folder	मेरे होम फ़ोल्डर में
EOF
}
lang_data_ar() { cat <<'EOF'
Let's set up your Minecraft server	لنقم بإعداد خادم ماين كرافت الخاص بك
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	استخدم مفاتيح الأسهم وEnter. اضغط Ctrl+C في أي وقت للخروج.
Nothing is installed until you confirm at the end.	لن يتم تثبيت أي شيء حتى تؤكد في النهاية.
How do you want to set up?	كيف تريد الإعداد؟
Simple - a few easy questions, everything else is chosen for you	بسيط: بضعة أسئلة سهلة والباقي يُختار تلقائيًا
Advanced - choose every option yourself	متقدم: اختر كل الخيارات بنفسك
What do you want to call your server?	ماذا تريد أن تسمي خادمك؟
Where should your server be saved? A new folder with your server's name is created there.	أين تريد حفظ الخادم؟ سيتم إنشاء مجلد جديد باسم الخادم هناك.
Next to this script (recommended)	بجانب هذا البرنامج النصي (موصى به)
On my Desktop	على سطح المكتب
In my Documents folder	في مجلد المستندات
Somewhere else (type a folder)	مكان آخر (اكتب مجلدًا)
Somewhere else (browse or type a folder)	مكان آخر (استعرض أو اكتب مجلدًا)
Your server will be installed in:	سيتم تثبيت الخادم في:
Yes, use this folder	نعم، استخدم هذا المجلد
No, pick another place	لا، اختر مكانًا آخر
Which kind of server do you want?	أي نوع من الخوادم تريد؟
Standard (recommended) - fast, and you can add plugins later	قياسي (موصى به): سريع ويمكنك إضافة الإضافات لاحقًا
Pure Minecraft - exactly like the official game	ماين كرافت الأصلي: تمامًا مثل اللعبة الرسمية
How will your friends join?	كيف سينضم أصدقاؤك؟
Over the internet - easiest, no router settings (free)	عبر الإنترنت: الأسهل، بلا إعدادات الراوتر (مجاني)
Over the internet using my router (port forwarding)	عبر الإنترنت باستخدام الراوتر (إعادة توجيه المنافذ)
Only people on my home Wi-Fi	فقط الأشخاص على شبكة الواي فاي المنزلية
Does everyone who will join own Minecraft (a paid Microsoft account)?	هل يملك كل من سينضم لعبة ماين كرافت (حساب مايكروسوفت مدفوع)؟
YES = safest, recommended.	نعم = الأكثر أمانًا، موصى به.
NO  = anyone can join with any name (only for friends you trust).	لا = يمكن لأي شخص الانضمام بأي اسم (لأصدقاء تثق بهم فقط).
Yes	نعم
No	لا
Finding the newest version ...	جارٍ البحث عن أحدث إصدار ...
Want to change more things (server message, icon, mods, whitelist, world...)?	هل تريد تغيير المزيد (الرسالة، الأيقونة، المودات، القائمة البيضاء، العالم...)؟
Most people choose No - you can still do that later.	يختار معظم الناس لا؛ يمكنك فعل ذلك لاحقًا.
Minecraft EULA	اتفاقية ترخيص ماين كرافت (EULA)
To run a server you must agree to the Minecraft End User License Agreement:	لتشغيل خادم يجب أن توافق على اتفاقية ترخيص المستخدم النهائي لماين كرافت:
Do you agree to the EULA?	هل توافق على الاتفاقية (EULA)؟
Summary	ملخص
Install now?	هل تريد التثبيت الآن؟
Installing your Minecraft server	جارٍ تثبيت خادم ماين كرافت الخاص بك
Step 1 of 4 - Checking Java	الخطوة 1 من 4: التحقق من Java
Step 2 of 4 - Downloading Minecraft (this can take a minute)	الخطوة 2 من 4: تنزيل ماين كرافت (قد يستغرق دقيقة)
Step 3 of 4 - Setting up internet access	الخطوة 3 من 4: إعداد الوصول عبر الإنترنت
Step 4 of 4 - Finishing up	الخطوة 4 من 4: اللمسات الأخيرة
Your server is ready	خادمك جاهز
To start your server, run:	لتشغيل الخادم، نفّذ:
To stop it, type  stop  in the server window.	لإيقافه اكتب  stop  في نافذة الخادم.
Friends join with:	ينضم أصدقاؤك عبر:
Note: anyone can join with any name. Only share the address with people you trust.	ملاحظة: يمكن لأي شخص الانضمام بأي اسم. شارك العنوان مع من تثق بهم فقط.
(Your playit.gg address. Keep playit running while you play.)	(عنوان playit.gg الخاص بك. أبقِ playit قيد التشغيل أثناء اللعب.)
(Only on the same Wi-Fi.)	(على نفس شبكة الواي فاي فقط.)
Start the server now?	هل تريد تشغيل الخادم الآن؟
All set - have fun!	كل شيء جاهز، استمتع!
Setup cancelled. Nothing was installed.	تم إلغاء الإعداد. لم يتم تثبيت أي شيء.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	هل تريد إعداد نفق playit.gg المجاني الآن بدليل خطوة بخطوة؟ (نحو 10 دقائق، ويمكنك لاحقًا)
playit.gg tunnel	نفق playit.gg
Name:	الاسم:
Type:	النوع:
Friends:	الأصدقاء:
Accounts:	الحسابات:
Memory:	الذاكرة:
Folder:	المجلد:
Standard	قياسي
Pure Minecraft	ماين كرافت الأصلي
over the internet (free tunnel)	عبر الإنترنت (نفق مجاني)
over the internet (router port forwarding)	عبر الإنترنت (إعادة توجيه المنافذ)
home Wi-Fi only	الواي فاي المنزلي فقط
everyone needs a Minecraft account	الجميع يحتاجون حساب ماين كرافت
anyone can join with any name	يمكن لأي شخص الانضمام بأي اسم
Press Enter to close	اضغط Enter للإغلاق
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	لست متأكدًا من أن هذه النافذة تستطيع عرض هذه اللغة. إذا ظهرت مربعات أو علامة ؟ بعد الاختيار، أعد التشغيل واختر الإنجليزية (يعمل Windows Terminal من متجر Microsoft بشكل أفضل).
Use this language	استخدام هذه اللغة
Use English instead	استخدام الإنجليزية بدلًا من ذلك
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	هذا الطرفية ليست مضبوطة على UTF-8، لذلك قد تظهر هذه اللغة بشكل خاطئ (مربعات أو ؟). هل تريد المتابعة بالإنجليزية؟
Use English	استخدام الإنجليزية
Try it anyway	جرّب على أي حال
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	نصيحة: إذا رأيت مربعات بدل الحروف، شغّل البرنامج مجددًا مع  -Lang en  أو استخدم Windows Terminal.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	نصيحة: إذا رأيت مربعات بدل الحروف، شغّل البرنامج مجددًا مع  --lang en  أو استخدم طرفية بخط يدعم هذه اللغة.
none	لا شيء
plugins	الإضافات
mods	التعديلات
Back	رجوع
Customise your server. Pick a category; choose 'done' when finished.	خصّص خادمك. اختر فئة، ثم اختر «تم» عند الانتهاء.
Server name: {0}	اسم الخادم: {0}
Server list message with colours: {0}	رسالة قائمة الخوادم بالألوان: {0}
Server icon: {0}	أيقونة الخادم: {0}
Mods: {0} queued	التعديلات: {0} في قائمة الانتظار
Plugins: {0} queued	الإضافات: {0} في قائمة الانتظار
Operators ({0}) and whitelist ({1})	المشرفون ({0}) والقائمة البيضاء ({1})
World type, seed, structures, nether, hardcore	نوع العالم، البذرة، الهياكل، النذر، الهاردكور
PvP, command blocks, flying, mobs, spawn protection	PvP، كتل الأوامر، الطيران، الكائنات، حماية نقطة الظهور
View / simulation distance: {0} / {1}	مسافة الرؤية / المحاكاة: {0} / {1}
Resource pack: {0}	حزمة الموارد: {0}
Any other server.properties setting ({0})	أي إعداد آخر في server.properties ({0})
Auto-restart on crash, backup script	إعادة تشغيل تلقائية عند التعطل، سكربت النسخ الاحتياطي
Finished customising	إنهاء التخصيص
Name of your server (e.g. Creeper Cove).	اسم خادمك (مثل Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	يُستخدم في عناوين النوافذ وإدخال التشغيل التلقائي والنسخ الاحتياطية، وإن لم تضبط رسالة بنفسك فسيظهر كرسالة في قائمة الخوادم.
Server list message (MOTD).	رسالة قائمة الخوادم (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	الألوان: &0 أسود &1 أزرق داكن &2 أخضر داكن &3 فيروزي داكن &4 أحمر داكن &5 بنفسجي &6 ذهبي
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 رمادي &8 رمادي داكن &9 أزرق &a أخضر &b سماوي &c أحمر &d وردي &e أصفر &f أبيض
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	الأنماط: &l عريض  &o مائل  &n تسطير  &k مبعثر  &r إعادة ضبط
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	استخدم \n لسطر ثانٍ.    مثال: &6&lMy Server\n&7Welcome!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	أيقونة الخادم: مسار صورة (png/jpg/gif...) أو رابط https://.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	يُحوَّل تلقائيًا إلى 64x64 بكسل (يُقصّ من الوسط إلى مربع).
Leave empty for no icon.	اتركه فارغًا لعدم استخدام أيقونة.
File not found: {0}	الملف غير موجود: {0}
Server icon created (64x64)	تم إنشاء أيقونة الخادم (64x64)
Checking which popular {0} work with Minecraft {1} ...	جارٍ فحص أي من {0} الشائعة يعمل مع Minecraft {1} ...
[not updated for {0} yet - newest version will be tried]	[لم يُحدَّث بعد لـ {0} - ستُجرَّب أحدث نسخة]
You already added everything in the popular list. Try the search option for more.	لقد أضفت كل ما في القائمة الشائعة. جرّب البحث للمزيد.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} جديد جدًا، لذا تم وسم {1} من الإضافات بأنها لم تُحدَّث بعد. غالبًا ما تعمل مع ذلك؛ اخترها إن أردت التجربة.
Pick the {0} you want (Space = tick, Enter = done, A = all)	اختر {0} التي تريدها (مسافة = تحديد، Enter = تم، A = الكل)
Added {0}	تمت إضافة {0}
Add {0}  ({1} queued, loader: {2})	إضافة {0}  ({1} في الانتظار، المُحمِّل: {2})
Add {0}  ({1} queued)	إضافة {0}  ({1} في الانتظار)
Pick from a list of popular {0}	اختر من قائمة {0} الشائعة
Search Modrinth for {0} (compatible with {1})	ابحث في Modrinth عن {0} (متوافقة مع {1})
Add direct https:// links to .jar files	إضافة روابط https:// مباشرة لملفات .jar
Show / remove queued {0}	عرض / إزالة {0} في الانتظار
Done with {0}	انتهيت من {0}
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	البحث في Modrinth ({0} لـ Minecraft {1}). أمثلة: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	فشل البحث في Modrinth.
Nothing found for '{0}' that works with Minecraft {1}.	لم يُعثر على شيء لـ «{0}» يعمل مع Minecraft {1}.
Results for '{0}':	نتائج «{0}»:
Added '{0}' (and any required dependencies).	تمت إضافة «{0}» (مع أي تبعيات مطلوبة).
Direct https:// links to .jar files, separated by spaces.	روابط https:// مباشرة لملفات .jar، مفصولة بمسافات.
Only use links from sources you trust - these files run on your server.	استخدم روابط من مصادر موثوقة فقط - هذه الملفات تعمل على خادمك.
Skipping '{0}' (must start with https://)	تم تخطي «{0}» (يجب أن يبدأ بـ https://)
Nothing queued yet.	لا شيء في قائمة الانتظار بعد.
Back (keep everything)	رجوع (الإبقاء على كل شيء)
Pick one to REMOVE from the install list:	اختر واحدًا لإزالته من قائمة التثبيت:
Skipping invalid name '{0}'	تم تخطي الاسم غير الصالح «{0}»
Operators (admins). Minecraft usernames separated by spaces or commas.	المشرفون (الإداريون). أسماء مستخدمي Minecraft مفصولة بمسافات أو فواصل.
Ops can use all commands.	يمكن للمشرفين استخدام جميع الأوامر.
Whitelist: only these players may join. Usernames separated by spaces or commas.	القائمة البيضاء: يمكن لهؤلاء اللاعبين فقط الانضمام. أسماء المستخدمين مفصولة بمسافات أو فواصل.
Leave empty to keep the whitelist as chosen earlier.	اتركه فارغًا للإبقاء على القائمة البيضاء المختارة سابقًا.
Could not look up '{0}' - add later with: whitelist add {0}	تعذّر البحث عن «{0}» - أضِفه لاحقًا بالأمر: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	تعذّر البحث عن «{0}» - أضِفه لاحقًا بالأمر: op {0}
World type:	نوع العالم:
Normal terrain	تضاريس عادية
Superflat	مسطّح تمامًا
Large biomes	مناطق حيوية كبيرة
Amplified (tall mountains)	مُضخَّم (جبال عالية)
World seed (empty = random):	بذرة العالم (فارغ = عشوائي):
World folder name:	اسم مجلد العالم:
Generate structures (villages, strongholds, ...)?	توليد الهياكل (قرى، حصون، ...)؟
Allow the Nether?	السماح بالنذر؟
Hardcore mode? (one life, forced hard difficulty)	وضع الهاردكور؟ (حياة واحدة، صعوبة صعبة إجبارية)
Allow player-vs-player combat (PvP)?	السماح بالقتال بين اللاعبين (PvP)؟
Enable command blocks?	تفعيل كتل الأوامر؟
Allow flying (needed for some mods; otherwise flight is kicked)?	السماح بالطيران؟ (مطلوب لبعض التعديلات؛ وإلا يُطرد الطائر)
Spawn animals?	ظهور الحيوانات؟
Spawn monsters?	ظهور الوحوش؟
Spawn villagers?	ظهور القرويين؟
Force everyone into the default game mode on every join?	فرض وضع اللعب الافتراضي على الجميع عند كل دخول؟
Spawn protection radius in blocks (0 = off):	نصف قطر حماية نقطة الظهور بالكتل (0 = إيقاف):
Kick idle players after N minutes (0 = never):	طرد اللاعبين الخاملين بعد N دقيقة (0 = أبدًا):
View distance in chunks (2-32). Lower = faster:	مسافة الرؤية بالقطع (2-32). الأقل = أسرع:
Simulation distance in chunks (2-32). Lower = faster:	مسافة المحاكاة بالقطع (2-32). الأقل = أسرع:
Please enter a number from {0} to {1}. Kept: {2}	أدخل رقمًا من {0} إلى {1}. تم الإبقاء على: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	حزمة موارد الخادم: رابط https:// مباشر لملف .zip (فارغ = لا شيء).
Players are offered it when they join. Its checksum is calculated at install time.	يُعرض على اللاعبين عند انضمامهم. تُحسب قيمة التحقق عند التثبيت.
That is not a link. Kept: {0}	هذا ليس رابطًا. تم الإبقاء على: {0}
Kick players who decline the resource pack?	طرد اللاعبين الذين يرفضون حزمة الموارد؟
Any other server.properties setting as key=value, separated by spaces.	أي إعداد آخر في server.properties بصيغة مفتاح=قيمة، مفصولة بمسافات.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	مثال: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	تم تخطي «{0}» (استخدم مفتاح=قيمة)
Restart the server automatically if it crashes?	إعادة تشغيل الخادم تلقائيًا إذا تعطل؟
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	إنشاء سكربت نسخ احتياطي (يضغط العالم في مجلد backups ويحتفظ بأحدث 10)؟
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	لا يمكن دمج محمّلات التعديلات مع إعداد Velocity هنا. (إضافات Paper ممكنة - اختر PaperMC.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla لا يدعم التعديلات بنفسه. اختر محمّل تعديلات (يحلّ محل خادم Vanilla العادي):
Fabric - lightweight, huge mod library (recommended)	Fabric - خفيف ومكتبة تعديلات ضخمة (موصى به)
NeoForge - big content mods (1.20.2+)	NeoForge - تعديلات محتوى كبيرة (1.20.2+)
Forge - classic loader (1.17+)	Forge - المحمّل الكلاسيكي (1.17+)
Plain Vanilla, no mods	Vanilla عادي بدون تعديلات
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	لا يوجد إصدار خادم لـ {0} مع Minecraft {1}. اختر محمّلًا آخر أو إصدار Minecraft آخر.
Modrinth lookup failed for '{0}'.	فشل البحث عن «{0}» في Modrinth.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	«{0}» غير موسوم بعد لـ {1} - أُضيفت أحدث نسخة منه ({2}). قد يعمل مع ذلك.
'{0}' has no download for {1} on this loader.	لا يوجد تنزيل لـ «{0}» مع {1} على هذا المحمّل.
Newest (recommended)	الأحدث (موصى بها)
Type a specific older version	اكتب إصدارًا أقدم محددًا
Which Minecraft version? (newest first)	أي إصدار من Minecraft؟ (الأحدث أولًا)
Type the exact Minecraft version (e.g. 1.20.1):	اكتب إصدار Minecraft بدقة (مثل 1.20.1):
That version is not available. Pick one from the list instead.	هذا الإصدار غير متاح. اختر واحدًا من القائمة.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	هل تريد السماح للاعبي Bedrock (الهواتف ووحدات التحكم وWindows 10/11) بالانضمام أيضًا؟
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	ينضمون عبر إضافة مجانية تسمى Geyser، فلا يحتاجون إلى حساب Java. تتطلب خادم Standard (Paper) الذي يُختار لك. تُضاف نقطة قبل أسماء Bedrock (مثل .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	هل تريد السماح للاعبي Bedrock بالانضمام أيضًا (Geyser + Floodgate)؟
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	يمكن حينها للاعبي Bedrock Edition (الهواتف ووحدات التحكم وWindows 10/11) الانضمام دون حساب Java. يتطلب PaperMC ويفتح منفذ UDP 19132. تُضاف نقطة قبل أسماء لاعبي Bedrock (مثل .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	تم التبديل إلى خادم Standard (PaperMC) لأن دعم Bedrock يتطلبه.
Downloading Geyser and Floodgate (Bedrock support) ...	جارٍ تنزيل Geyser وFloodgate (دعم Bedrock) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	تم تثبيت دعم Bedrock (Geyser + Floodgate، UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	يمكن للهواتف ووحدات التحكم وWindows 10/11 الانضمام أيضًا
Bedrock players (phones, consoles, Windows 10/11) join with:	لاعبو Bedrock (الهواتف ووحدات التحكم وWindows 10/11) ينضمون عبر:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(في Minecraft Bedrock: Play > Servers > Add Server. تُضاف نقطة قبل أسمائهم، مثل .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	نصيحة: أوقف الخادم أولًا (اكتب  stop  في نافذته). تُقرأ التغييرات عند التشغيل.
What do you want to change?	ماذا تريد أن تغيّر؟
Server icon	أيقونة الخادم
Add plugins	إضافة إضافات
Add mods	إضافة تعديلات
Remove plugins	إزالة إضافات
Remove mods	إزالة تعديلات
Any other server.properties setting	أي إعداد آخر في server.properties
Change the Minecraft version (now {0})	تغيير إصدار Minecraft (الحالي {0})
Bedrock players: ON (Geyser + Floodgate)	لاعبو Bedrock: مفعّل (Geyser + Floodgate)
Bedrock players: off	لاعبو Bedrock: متوقف
Make a backup now	إنشاء نسخة احتياطية الآن
Saved.	تم الحفظ.
All done. Start (or restart) your server to use the changes.	تم كل شيء. شغّل خادمك (أو أعد تشغيله) لاستخدام التغييرات.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	تغيير البذرة أو نوع العالم أو اسم مجلد العالم يؤثر على عالم جديد فقط. عالمك الحالي يبقى كما هو.
Backup saved: {0}	تم حفظ النسخة الاحتياطية: {0}
Making a backup first ...	جارٍ إنشاء نسخة احتياطية أولًا ...
The backup failed - stopping here so nothing is lost.	فشل النسخ الاحتياطي - أتوقف هنا حتى لا يضيع شيء.
Which server do you want to change?	أي خادم تريد تغييره؟
Pick another folder ...	اختر مجلدًا آخر ...
Type the folder of your server (the one that contains start-all):	اكتب مجلد خادمك (الذي يحتوي على start-all):
That folder does not look like a server made by this tool.	لا يبدو هذا المجلد خادمًا أنشأته هذه الأداة.
{0} file(s) placed in {1}	تم وضع {0} ملف في {1}
Nothing is installed in this folder yet.	لا يوجد شيء مثبّت في هذا المجلد بعد.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	حدد ما تريد إزالته (يُنقل إلى مجلد اسمه removed ولا يُحذف)
Removed {0}	تمت إزالة {0}
Fetching version list ...	جارٍ جلب قائمة الإصدارات ...
Could not get the version list (is the internet working?).	تعذّر الحصول على قائمة الإصدارات (هل الإنترنت يعمل؟).
That is the version you already have.	هذا هو الإصدار الذي لديك بالفعل.
Change Minecraft from {0} to {1}?	تغيير Minecraft من {0} إلى {1}؟
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	لا يمكن للعوالم الرجوع إلى إصدار أقدم، لذا تُنشأ نسخة احتياطية كاملة أولًا. قد تحتاج الإضافات والتعديلات إلى تحديث بعد ذلك.
Now on Minecraft {0}	الآن على Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	إذا توقفت إضافة أو تعديل عن العمل مع الإصدار الجديد، فحدّثه أو أزله من هذه القائمة. وللرجوع، استعد النسخة الاحتياطية من مجلد backups.
This loader has no release for that version.	لا يوجد إصدار من هذا المحمّل لتلك النسخة.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	دعم Bedrock مفعّل. هل تريد إيقافه؟ (يُنقل Geyser وFloodgate إلى مجلد اسمه removed.)
Bedrock support turned off.	تم إيقاف دعم Bedrock.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	يتطلب دعم Bedrock هنا خادم PaperMC عاديًا (وليس Velocity أو Fabric أو Forge).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	هل تريد السماح للاعبي Bedrock (الهواتف ووحدات التحكم وWindows 10/11) بالانضمام أيضًا؟
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	تُضاف Geyser وFloodgate. تتطلبان PaperMC. تُضاف نقطة قبل أسماء Bedrock (مثل .Steve). يُستخدم منفذ UDP {0}.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	خادمك Vanilla. هل تريد التحويل إلى PaperMC (الإصدار نفسه والعالم نفسه)؟ تُنشأ نسخة احتياطية كاملة أولًا.
PaperMC has no build for this version.	لا يوجد إصدار PaperMC لهذه النسخة.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	يحتاج لاعبو Bedrock إلى منفذ UDP {0} متاح. مع playit.gg شغّل  bash mc-setup.sh --tunnel-guide  لإضافة نفق Bedrock؛ ومع الراوتر وجّه UDP {0} أيضًا.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	يحتاج لاعبو Bedrock إلى منفذ UDP {0} متاح. مع playit.gg شغّل  powershell -File mc-setup.ps1 -TunnelGuide  لإضافة نفق Bedrock؛ ومع الراوتر وجّه UDP {0} أيضًا.
In my home folder	في مجلد المنزل الخاص بي
EOF
}
lang_data_he() { cat <<'EOF'
Let's set up your Minecraft server	בוא נגדיר את שרת ה-Minecraft שלך
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	השתמש בחצים וב-Enter. לחץ Ctrl+C בכל עת כדי לצאת.
Nothing is installed until you confirm at the end.	שום דבר לא יותקן עד שתאשר בסוף.
How do you want to set up?	איך תרצה להגדיר?
Simple - a few easy questions, everything else is chosen for you	פשוט: כמה שאלות קלות, השאר נבחר בשבילך
Advanced - choose every option yourself	מתקדם: בחר כל אפשרות בעצמך
What do you want to call your server?	איך תרצה לקרוא לשרת שלך?
Where should your server be saved? A new folder with your server's name is created there.	היכן לשמור את השרת? ייווצר שם תיקייה חדשה בשם השרת.
Next to this script (recommended)	ליד הסקריפט הזה (מומלץ)
On my Desktop	בשולחן העבודה
In my Documents folder	בתיקיית המסמכים
Somewhere else (type a folder)	מקום אחר (הקלד תיקייה)
Somewhere else (browse or type a folder)	מקום אחר (עיין או הקלד תיקייה)
Your server will be installed in:	השרת יותקן ב:
Yes, use this folder	כן, השתמש בתיקייה הזו
No, pick another place	לא, בחר מקום אחר
Which kind of server do you want?	איזה סוג שרת אתה רוצה?
Standard (recommended) - fast, and you can add plugins later	רגיל (מומלץ): מהיר, ואפשר להוסיף תוספים מאוחר יותר
Pure Minecraft - exactly like the official game	Minecraft טהור: בדיוק כמו המשחק הרשמי
How will your friends join?	איך החברים שלך יצטרפו?
Over the internet - easiest, no router settings (free)	דרך האינטרנט: הכי קל, בלי הגדרות נתב (חינם)
Over the internet using my router (port forwarding)	דרך האינטרנט באמצעות הנתב שלי (העברת פורטים)
Only people on my home Wi-Fi	רק אנשים ברשת ה-Wi-Fi הביתית שלי
Does everyone who will join own Minecraft (a paid Microsoft account)?	האם לכל מי שיצטרף יש Minecraft (חשבון Microsoft בתשלום)?
YES = safest, recommended.	כן = הכי בטוח, מומלץ.
NO  = anyone can join with any name (only for friends you trust).	לא = כל אחד יכול להצטרף בכל שם (רק לחברים שאתה סומך עליהם).
Yes	כן
No	לא
Finding the newest version ...	מחפש את הגרסה החדשה ביותר ...
Want to change more things (server message, icon, mods, whitelist, world...)?	רוצה לשנות עוד דברים (הודעה, אייקון, מודים, רשימה לבנה, עולם...)?
Most people choose No - you can still do that later.	רוב האנשים בוחרים לא; אפשר לעשות זאת גם אחר כך.
Minecraft EULA	הסכם הרישיון של Minecraft (EULA)
To run a server you must agree to the Minecraft End User License Agreement:	כדי להריץ שרת עליך להסכים להסכם הרישיון למשתמש הקצה של Minecraft:
Do you agree to the EULA?	האם אתה מסכים ל-EULA?
Summary	סיכום
Install now?	להתקין עכשיו?
Installing your Minecraft server	מתקין את שרת ה-Minecraft שלך
Step 1 of 4 - Checking Java	שלב 1 מתוך 4: בדיקת Java
Step 2 of 4 - Downloading Minecraft (this can take a minute)	שלב 2 מתוך 4: מוריד את Minecraft (עלול לקחת דקה)
Step 3 of 4 - Setting up internet access	שלב 3 מתוך 4: הגדרת גישה מהאינטרנט
Step 4 of 4 - Finishing up	שלב 4 מתוך 4: סיום
Your server is ready	השרת שלך מוכן
To start your server, run:	כדי להפעיל את השרת, הרץ:
To stop it, type  stop  in the server window.	כדי לעצור, הקלד  stop  בחלון השרת.
Friends join with:	החברים מצטרפים עם:
Note: anyone can join with any name. Only share the address with people you trust.	שים לב: כל אחד יכול להצטרף בכל שם. שתף את הכתובת רק עם אנשים שאתה סומך עליהם.
(Your playit.gg address. Keep playit running while you play.)	(כתובת ה-playit.gg שלך. השאר את playit פועל בזמן המשחק.)
(Only on the same Wi-Fi.)	(רק באותה רשת Wi-Fi.)
Start the server now?	להפעיל את השרת עכשיו?
All set - have fun!	הכול מוכן, תהנה!
Setup cancelled. Nothing was installed.	ההתקנה בוטלה. דבר לא הותקן.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	להגדיר עכשיו את מנהרת playit.gg החינמית עם מדריך שלב אחר שלב? (כ-10 דקות, אפשר גם אחר כך)
playit.gg tunnel	מנהרת playit.gg
Name:	שם:
Type:	סוג:
Friends:	חברים:
Accounts:	חשבונות:
Memory:	זיכרון:
Folder:	תיקייה:
Standard	רגיל
Pure Minecraft	Minecraft טהור
over the internet (free tunnel)	דרך האינטרנט (מנהרה חינמית)
over the internet (router port forwarding)	דרך האינטרנט (העברת פורטים)
home Wi-Fi only	Wi-Fi ביתי בלבד
everyone needs a Minecraft account	כולם צריכים חשבון Minecraft
anyone can join with any name	כל אחד יכול להצטרף בכל שם
Press Enter to close	לחץ Enter לסגירה
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	לא בטוח שהחלון הזה יכול להציג את השפה הזו. אם אחרי הבחירה אתה רואה ריבועים או ?, הפעל מחדש ובחר אנגלית (Windows Terminal מחנות Microsoft עובד הכי טוב).
Use this language	להשתמש בשפה הזו
Use English instead	להשתמש באנגלית במקום
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	הטרמינל הזה לא מוגדר ל-UTF-8, ולכן השפה עלולה להיראות שבורה (ריבועים או ?). להמשיך באנגלית?
Use English	להשתמש באנגלית
Try it anyway	לנסות בכל זאת
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	טיפ: אם אתה רואה ריבועים במקום אותיות, הפעל שוב עם  -Lang en  או השתמש ב-Windows Terminal.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	טיפ: אם אתה רואה ריבועים במקום אותיות, הפעל שוב עם  --lang en  או השתמש בטרמינל עם גופן שתומך בשפה.
none	ללא
plugins	תוספים
mods	מודים
Back	חזרה
Customise your server. Pick a category; choose 'done' when finished.	התאימו את השרת. בחרו קטגוריה; בסיום בחרו ״סיום״.
Server name: {0}	שם השרת: {0}
Server list message with colours: {0}	הודעת רשימת השרתים עם צבעים: {0}
Server icon: {0}	אייקון השרת: {0}
Mods: {0} queued	מודים: {0} בתור
Plugins: {0} queued	תוספים: {0} בתור
Operators ({0}) and whitelist ({1})	מפעילים ({0}) ורשימה לבנה ({1})
World type, seed, structures, nether, hardcore	סוג עולם, סיד, מבנים, נדר, הארדקור
PvP, command blocks, flying, mobs, spawn protection	PvP, בלוקי פקודה, תעופה, מובס, הגנת ספאון
View / simulation distance: {0} / {1}	טווח ראייה / סימולציה: {0} / {1}
Resource pack: {0}	חבילת משאבים: {0}
Any other server.properties setting ({0})	כל הגדרה אחרת ב-server.properties ({0})
Auto-restart on crash, backup script	הפעלה מחדש אוטומטית בקריסה, סקריפט גיבוי
Finished customising	סיום ההתאמה
Name of your server (e.g. Creeper Cove).	שם השרת שלכם (למשל Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	משמש לכותרות חלונות, להפעלה אוטומטית, לגיבויים, ואם לא הגדרתם הודעה בעצמכם – גם כהודעה ברשימת השרתים.
Server list message (MOTD).	הודעת רשימת השרתים (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	צבעים: &0 שחור &1 כחול כהה &2 ירוק כהה &3 תכלת כהה &4 אדום כהה &5 סגול &6 זהב
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 אפור &8 אפור כהה &9 כחול &a ירוק &b תכלת &c אדום &d ורוד &e צהוב &f לבן
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	סגנונות: &l מודגש  &o נטוי  &n קו תחתון  &k מעורבב  &r איפוס
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	השתמשו ב-\n לשורה שנייה.    דוגמה: &6&lMy Server\n&7Welcome!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	אייקון השרת: נתיב לתמונה (png/jpg/gif...) או קישור https://.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	הוא מומר אוטומטית ל-64x64 פיקסלים (נחתך מהמרכז לריבוע).
Leave empty for no icon.	השאירו ריק לללא אייקון.
File not found: {0}	הקובץ לא נמצא: {0}
Server icon created (64x64)	אייקון השרת נוצר (64x64)
Checking which popular {0} work with Minecraft {1} ...	בודק אילו {0} פופולריים עובדים עם Minecraft {1} ...
[not updated for {0} yet - newest version will be tried]	[עדיין לא עודכן ל-{0} - תיבחן הגרסה החדשה ביותר]
You already added everything in the popular list. Try the search option for more.	כבר הוספתם את כל מה שברשימה הפופולרית. נסו את החיפוש כדי למצוא עוד.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} חדש מאוד, ולכן {1} תוספים מסומנים כלא מעודכנים עדיין. לרוב הם עדיין עובדים; בחרו בהם אם תרצו לנסות.
Pick the {0} you want (Space = tick, Enter = done, A = all)	בחרו את ה{0} שתרצו (רווח = סימון, Enter = סיום, A = הכול)
Added {0}	{0} נוסף
Add {0}  ({1} queued, loader: {2})	הוספת {0}  ({1} בתור, טוען: {2})
Add {0}  ({1} queued)	הוספת {0}  ({1} בתור)
Pick from a list of popular {0}	בחירה מרשימת {0} פופולריים
Search Modrinth for {0} (compatible with {1})	חיפוש {0} ב-Modrinth (תואמים ל-{1})
Add direct https:// links to .jar files	הוספת קישורי https:// ישירים לקובצי .jar
Show / remove queued {0}	הצגה / הסרה של {0} בתור
Done with {0}	סיימתי עם {0}
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	חיפוש ב-Modrinth ({0} עבור Minecraft {1}). דוגמאות: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	החיפוש ב-Modrinth נכשל.
Nothing found for '{0}' that works with Minecraft {1}.	לא נמצא דבר עבור ״{0}״ שעובד עם Minecraft {1}.
Results for '{0}':	תוצאות עבור ״{0}״:
Added '{0}' (and any required dependencies).	״{0}״ נוסף (וכן כל התלויות הנדרשות).
Direct https:// links to .jar files, separated by spaces.	קישורי https:// ישירים לקובצי .jar, מופרדים ברווחים.
Only use links from sources you trust - these files run on your server.	השתמשו רק בקישורים ממקורות שאתם סומכים עליהם - הקבצים האלה רצים על השרת שלכם.
Skipping '{0}' (must start with https://)	מדלג על ״{0}״ (חייב להתחיל ב-https://)
Nothing queued yet.	עדיין אין דבר בתור.
Back (keep everything)	חזרה (להשאיר הכול)
Pick one to REMOVE from the install list:	בחרו אחד להסרה מרשימת ההתקנה:
Skipping invalid name '{0}'	מדלג על שם לא תקין ״{0}״
Operators (admins). Minecraft usernames separated by spaces or commas.	מפעילים (אדמינים). שמות משתמש של Minecraft מופרדים ברווחים או בפסיקים.
Ops can use all commands.	מפעילים יכולים להשתמש בכל הפקודות.
Whitelist: only these players may join. Usernames separated by spaces or commas.	רשימה לבנה: רק השחקנים האלה יכולים להצטרף. שמות משתמש מופרדים ברווחים או בפסיקים.
Leave empty to keep the whitelist as chosen earlier.	השאירו ריק כדי לשמור על הרשימה הלבנה שנבחרה קודם.
Could not look up '{0}' - add later with: whitelist add {0}	לא ניתן היה לאתר את ״{0}״ - הוסיפו מאוחר יותר עם: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	לא ניתן היה לאתר את ״{0}״ - הוסיפו מאוחר יותר עם: op {0}
World type:	סוג העולם:
Normal terrain	שטח רגיל
Superflat	שטוח במיוחד
Large biomes	ביומות גדולים
Amplified (tall mountains)	מוגבר (הרים גבוהים)
World seed (empty = random):	סיד העולם (ריק = אקראי):
World folder name:	שם תיקיית העולם:
Generate structures (villages, strongholds, ...)?	ליצור מבנים (כפרים, מבצרים, ...)?
Allow the Nether?	לאפשר את הנדר?
Hardcore mode? (one life, forced hard difficulty)	מצב הארדקור? (חיים אחד, קושי קשה בכפייה)
Allow player-vs-player combat (PvP)?	לאפשר קרב בין שחקנים (PvP)?
Enable command blocks?	להפעיל בלוקי פקודה?
Allow flying (needed for some mods; otherwise flight is kicked)?	לאפשר תעופה? (נחוץ לחלק מהמודים; אחרת מי שמעופף מנותק)
Spawn animals?	להוליד חיות?
Spawn monsters?	להוליד מפלצות?
Spawn villagers?	להוליד כפריים?
Force everyone into the default game mode on every join?	לכפות על כולם את מצב המשחק ברירת המחדל בכל הצטרפות?
Spawn protection radius in blocks (0 = off):	רדיוס הגנת ספאון בבלוקים (0 = כבוי):
Kick idle players after N minutes (0 = never):	לנתק שחקנים לא פעילים אחרי N דקות (0 = לעולם לא):
View distance in chunks (2-32). Lower = faster:	טווח ראייה בצ'אנקים (2-32). נמוך = מהיר יותר:
Simulation distance in chunks (2-32). Lower = faster:	טווח סימולציה בצ'אנקים (2-32). נמוך = מהיר יותר:
Please enter a number from {0} to {1}. Kept: {2}	הזינו מספר בין {0} ל-{1}. נשמר: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	חבילת משאבים לשרת: קישור https:// ישיר לקובץ .zip (ריק = ללא).
Players are offered it when they join. Its checksum is calculated at install time.	מוצע לשחקנים בעת ההצטרפות. סכום הביקורת מחושב בזמן ההתקנה.
That is not a link. Kept: {0}	זה לא קישור. נשמר: {0}
Kick players who decline the resource pack?	לנתק שחקנים שמסרבים לחבילת המשאבים?
Any other server.properties setting as key=value, separated by spaces.	כל הגדרה אחרת ב-server.properties בצורת מפתח=ערך, מופרדות ברווחים.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	דוגמה: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	מדלג על ״{0}״ (השתמשו במפתח=ערך)
Restart the server automatically if it crashes?	להפעיל מחדש את השרת אוטומטית אם הוא קורס?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	ליצור סקריפט גיבוי? (דוחס את העולם לתיקיית backups, שומר את 10 האחרונים)
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	לא ניתן לשלב כאן טוענים של מודים עם התצורה של Velocity. (תוספי Paper כן - בחרו PaperMC.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	ל-Vanilla אין תמיכה במודים בעצמו. בחרו טוען מודים (הוא מחליף את שרת ה-Vanilla הרגיל):
Fabric - lightweight, huge mod library (recommended)	Fabric - קל, ספריית מודים עצומה (מומלץ)
NeoForge - big content mods (1.20.2+)	NeoForge - מודי תוכן גדולים (1.20.2+)
Forge - classic loader (1.17+)	Forge - טוען קלאסי (1.17+)
Plain Vanilla, no mods	Vanilla רגיל, ללא מודים
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	ל-{0} אין גרסת שרת עבור Minecraft {1}. בחרו טוען אחר או גרסת Minecraft אחרת.
Modrinth lookup failed for '{0}'.	הבדיקה של ״{0}״ ב-Modrinth נכשלה.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	״{0}״ עדיין לא מסומן עבור {1} - נוספה הגרסה החדשה ביותר שלו ({2}). ייתכן שעדיין יעבוד.
'{0}' has no download for {1} on this loader.	ל-״{0}״ אין הורדה עבור {1} בטוען הזה.
Newest (recommended)	החדשה ביותר (מומלץ)
Type a specific older version	הקלידו גרסה ישנה מסוימת
Which Minecraft version? (newest first)	איזו גרסת Minecraft? (החדשה ביותר ראשונה)
Type the exact Minecraft version (e.g. 1.20.1):	הקלידו את גרסת Minecraft המדויקת (למשל 1.20.1):
That version is not available. Pick one from the list instead.	הגרסה הזו אינה זמינה. בחרו אחת מהרשימה.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	האם גם שחקני Bedrock (טלפונים, קונסולות, Windows 10/11) יוכלו להצטרף?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	הם מצטרפים דרך תוסף חינמי בשם Geyser, ולכן אין להם צורך בחשבון Java. נדרש שרת רגיל (Paper), שנבחר עבורכם. לשמות של Bedrock מתווספת נקודה בהתחלה (למשל .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	לאפשר גם לשחקני Bedrock להצטרף (Geyser + Floodgate)?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	שחקני Bedrock Edition (טלפונים, קונסולות, Windows 10/11) יוכלו אז להצטרף בלי חשבון Java. נדרש PaperMC ונפתחת יציאת UDP 19132. לשמות שחקני Bedrock מתווספת נקודה בהתחלה (למשל .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	עברנו לשרת הרגיל (PaperMC) כי תמיכת Bedrock דורשת אותו.
Downloading Geyser and Floodgate (Bedrock support) ...	מוריד את Geyser ו-Floodgate (תמיכת Bedrock) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	תמיכת Bedrock הותקנה (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	גם טלפונים, קונסולות ו-Windows 10/11 יכולים להצטרף
Bedrock players (phones, consoles, Windows 10/11) join with:	שחקני Bedrock (טלפונים, קונסולות, Windows 10/11) מצטרפים עם:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(ב-Minecraft Bedrock: Play > Servers > Add Server. לשמות שלהם מתווספת נקודה בהתחלה, כמו .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	טיפ: עצרו קודם את השרת (הקלידו  stop  בחלון שלו). השינויים נקראים בעת ההפעלה.
What do you want to change?	מה תרצו לשנות?
Server icon	אייקון השרת
Add plugins	הוספת תוספים
Add mods	הוספת מודים
Remove plugins	הסרת תוספים
Remove mods	הסרת מודים
Any other server.properties setting	כל הגדרה אחרת ב-server.properties
Change the Minecraft version (now {0})	שינוי גרסת Minecraft (כעת {0})
Bedrock players: ON (Geyser + Floodgate)	שחקני Bedrock: פעיל (Geyser + Floodgate)
Bedrock players: off	שחקני Bedrock: כבוי
Make a backup now	יצירת גיבוי עכשיו
Saved.	נשמר.
All done. Start (or restart) your server to use the changes.	הכול מוכן. הפעילו (או הפעילו מחדש) את השרת כדי להשתמש בשינויים.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	שינוי הסיד, סוג העולם או שם תיקיית העולם משפיע רק על עולם חדש. העולם הנוכחי שלכם נשאר כפי שהוא.
Backup saved: {0}	הגיבוי נשמר: {0}
Making a backup first ...	יוצר גיבוי קודם ...
The backup failed - stopping here so nothing is lost.	הגיבוי נכשל - עוצר כאן כדי שלא יאבד דבר.
Which server do you want to change?	איזה שרת תרצו לשנות?
Pick another folder ...	בחירת תיקייה אחרת ...
Type the folder of your server (the one that contains start-all):	הקלידו את תיקיית השרת שלכם (זו שמכילה את start-all):
That folder does not look like a server made by this tool.	התיקייה הזו לא נראית כשרת שנוצר בכלי הזה.
{0} file(s) placed in {1}	{0} קבצים הונחו ב-{1}
Nothing is installed in this folder yet.	עדיין לא מותקן דבר בתיקייה הזו.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	סמנו את מה שרוצים להסיר (הם מועברים לתיקייה בשם removed, לא נמחקים)
Removed {0}	{0} הוסר
Fetching version list ...	מביא את רשימת הגרסאות ...
Could not get the version list (is the internet working?).	לא ניתן היה להביא את רשימת הגרסאות (האינטרנט עובד?).
That is the version you already have.	זו הגרסה שכבר יש לכם.
Change Minecraft from {0} to {1}?	לשנות את Minecraft מ-{0} ל-{1}?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	עולמות אינם יכולים לחזור לגרסה ישנה יותר, ולכן נוצר קודם גיבוי מלא. ייתכן שיהיה צורך לעדכן תוספים ומודים אחר כך.
Now on Minecraft {0}	כעת ב-Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	אם תוסף או מוד מפסיק לעבוד עם הגרסה החדשה, עדכנו או הסירו אותו מהתפריט הזה. כדי לחזור אחורה, שחזרו את הגיבוי מתיקיית backups.
This loader has no release for that version.	לטוען הזה אין מהדורה לגרסה הזו.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	תמיכת Bedrock פעילה. לכבות אותה? (Geyser ו-Floodgate יועברו לתיקייה בשם removed.)
Bedrock support turned off.	תמיכת Bedrock כובתה.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	תמיכת Bedrock כאן דורשת שרת PaperMC רגיל (לא Velocity, Fabric או Forge).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	לאפשר גם לשחקני Bedrock (טלפונים, קונסולות, Windows 10/11) להצטרף?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Geyser ו-Floodgate יתווספו. הם דורשים PaperMC. לשמות של Bedrock מתווספת נקודה בהתחלה (למשל .Steve). נעשה שימוש ביציאת UDP {0}.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	השרת שלכם הוא Vanilla. לעבור ל-PaperMC (אותה גרסה, אותו עולם)? קודם נוצר גיבוי מלא.
PaperMC has no build for this version.	ל-PaperMC אין בנייה לגרסה הזו.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	שחקני Bedrock זקוקים ליציאת UDP {0} נגישה. עם playit.gg הריצו  bash mc-setup.sh --tunnel-guide  כדי להוסיף מנהרת Bedrock; עם נתב, הפנו גם את UDP {0}.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	שחקני Bedrock זקוקים ליציאת UDP {0} נגישה. עם playit.gg הריצו  powershell -File mc-setup.ps1 -TunnelGuide  כדי להוסיף מנהרת Bedrock; עם נתב, הפנו גם את UDP {0}.
In my home folder	בתיקיית הבית שלי
EOF
}
lang_data_tr() { cat <<'EOF'
Let's set up your Minecraft server	Minecraft sunucunu kuralım
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	Ok tuşları ve Enter'ı kullan. İstediğin zaman çıkmak için Ctrl+C'ye bas.
Nothing is installed until you confirm at the end.	Sonunda onaylayana kadar hiçbir şey kurulmaz.
How do you want to set up?	Nasıl kurmak istersin?
Simple - a few easy questions, everything else is chosen for you	Basit: birkaç kolay soru, gerisi senin için seçilir
Advanced - choose every option yourself	Gelişmiş: her seçeneği kendin seç
What do you want to call your server?	Sunucuna ne ad vermek istersin?
Where should your server be saved? A new folder with your server's name is created there.	Sunucun nereye kaydedilsin? Orada sunucunun adıyla yeni bir klasör oluşturulur.
Next to this script (recommended)	Bu betiğin yanında (önerilir)
On my Desktop	Masaüstümde
In my Documents folder	Belgelerim klasöründe
Somewhere else (type a folder)	Başka bir yer (klasör yaz)
Somewhere else (browse or type a folder)	Başka bir yer (gözat veya klasör yaz)
Your server will be installed in:	Sunucun şuraya kurulacak:
Yes, use this folder	Evet, bu klasörü kullan
No, pick another place	Hayır, başka yer seç
Which kind of server do you want?	Hangi tür sunucu istiyorsun?
Standard (recommended) - fast, and you can add plugins later	Standart (önerilir): hızlı, eklentileri sonra ekleyebilirsin
Pure Minecraft - exactly like the official game	Saf Minecraft: resmi oyunun aynısı
How will your friends join?	Arkadaşların nasıl katılacak?
Over the internet - easiest, no router settings (free)	İnternet üzerinden: en kolayı, router ayarı yok (ücretsiz)
Over the internet using my router (port forwarding)	İnternet üzerinden, router ile (port yönlendirme)
Only people on my home Wi-Fi	Yalnızca ev Wi-Fi ağımdaki kişiler
Does everyone who will join own Minecraft (a paid Microsoft account)?	Katılacak herkesin Minecraft'ı var mı (ücretli Microsoft hesabı)?
YES = safest, recommended.	EVET = en güvenli, önerilir.
NO  = anyone can join with any name (only for friends you trust).	HAYIR = herkes istediği adla katılabilir (yalnızca güvendiğin arkadaşlar için).
Yes	Evet
No	Hayır
Finding the newest version ...	En yeni sürüm aranıyor ...
Want to change more things (server message, icon, mods, whitelist, world...)?	Daha fazlasını değiştirmek ister misin (mesaj, simge, modlar, beyaz liste, dünya...)?
Most people choose No - you can still do that later.	Çoğu kişi Hayır der; bunu sonra da yapabilirsin.
Minecraft EULA	Minecraft EULA (Lisans Sözleşmesi)
To run a server you must agree to the Minecraft End User License Agreement:	Sunucu çalıştırmak için Minecraft Son Kullanıcı Lisans Sözleşmesi'ni kabul etmelisin:
Do you agree to the EULA?	EULA'yı kabul ediyor musun?
Summary	Özet
Install now?	Şimdi kurulsun mu?
Installing your Minecraft server	Minecraft sunucun kuruluyor
Step 1 of 4 - Checking Java	Adım 1/4: Java kontrol ediliyor
Step 2 of 4 - Downloading Minecraft (this can take a minute)	Adım 2/4: Minecraft indiriliyor (bir dakika sürebilir)
Step 3 of 4 - Setting up internet access	Adım 3/4: internet erişimi ayarlanıyor
Step 4 of 4 - Finishing up	Adım 4/4: son işlemler
Your server is ready	Sunucun hazır
To start your server, run:	Sunucunu başlatmak için şunu çalıştır:
To stop it, type  stop  in the server window.	Durdurmak için sunucu penceresine  stop  yaz.
Friends join with:	Arkadaşların şununla katılır:
Note: anyone can join with any name. Only share the address with people you trust.	Not: herkes istediği adla katılabilir. Adresi yalnızca güvendiğin kişilerle paylaş.
(Your playit.gg address. Keep playit running while you play.)	(playit.gg adresin. Oynarken playit'i açık tut.)
(Only on the same Wi-Fi.)	(Yalnızca aynı Wi-Fi'de.)
Start the server now?	Sunucu şimdi başlatılsın mı?
All set - have fun!	Hepsi tamam, iyi eğlenceler!
Setup cancelled. Nothing was installed.	Kurulum iptal edildi. Hiçbir şey kurulmadı.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	Ücretsiz playit.gg tünelini adım adım rehberle şimdi kuralım mı? (yaklaşık 10 dakika, sonra da yapabilirsin)
playit.gg tunnel	playit.gg tüneli
Name:	Ad:
Type:	Tür:
Friends:	Arkadaşlar:
Accounts:	Hesaplar:
Memory:	Bellek:
Folder:	Klasör:
Standard	Standart
Pure Minecraft	Saf Minecraft
over the internet (free tunnel)	internet üzerinden (ücretsiz tünel)
over the internet (router port forwarding)	internet üzerinden (port yönlendirme)
home Wi-Fi only	yalnızca ev Wi-Fi'ı
everyone needs a Minecraft account	herkesin Minecraft hesabı gerekir
anyone can join with any name	herkes istediği adla katılabilir
Press Enter to close	Kapatmak için Enter'a bas
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	Bu pencerenin bu dili gösterip gösteremeyeceğinden emin değilim. Seçtikten sonra kareler veya ? görürsen yeniden başlat ve İngilizce'yi seç (Microsoft Store'daki Windows Terminal en iyi sonucu verir).
Use this language	Bu dili kullan
Use English instead	Bunun yerine İngilizce kullan
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	Bu terminal UTF-8 olarak ayarlı değil, bu yüzden bu dil bozuk görünebilir (kareler veya ?). İngilizce devam edilsin mi?
Use English	İngilizce kullan
Try it anyway	Yine de dene
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	İpucu: Harfler yerine kareler görüyorsan  -Lang en  ile yeniden çalıştır veya Windows Terminal kullan.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	İpucu: Harfler yerine kareler görüyorsan  --lang en  ile yeniden çalıştır veya bu dili destekleyen yazı tipli bir terminal kullan.
none	yok
plugins	eklentiler
mods	modlar
Back	Geri
Customise your server. Pick a category; choose 'done' when finished.	Sunucunu özelleştir. Bir kategori seç; bitince «bitti»yi seç.
Server name: {0}	Sunucu adı: {0}
Server list message with colours: {0}	Renkli sunucu listesi mesajı: {0}
Server icon: {0}	Sunucu simgesi: {0}
Mods: {0} queued	Modlar: {0} sırada
Plugins: {0} queued	Eklentiler: {0} sırada
Operators ({0}) and whitelist ({1})	Operatörler ({0}) ve beyaz liste ({1})
World type, seed, structures, nether, hardcore	Dünya türü, tohum, yapılar, Nether, hardcore
PvP, command blocks, flying, mobs, spawn protection	PvP, komut blokları, uçma, yaratıklar, doğma koruması
View / simulation distance: {0} / {1}	Görüş / simülasyon mesafesi: {0} / {1}
Resource pack: {0}	Kaynak paketi: {0}
Any other server.properties setting ({0})	Diğer herhangi bir server.properties ayarı ({0})
Auto-restart on crash, backup script	Çökünce otomatik yeniden başlatma, yedekleme betiği
Finished customising	Özelleştirmeyi bitir
Name of your server (e.g. Creeper Cove).	Sunucunun adı (ör. Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	Pencere başlıklarında, otomatik başlatma girişinde, yedeklerde ve kendin bir mesaj belirlemediysen sunucu listesinde mesaj olarak kullanılır.
Server list message (MOTD).	Sunucu listesi mesajı (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	Renkler: &0 siyah &1 koyu mavi &2 koyu yeşil &3 koyu turkuaz &4 koyu kırmızı &5 mor &6 altın
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 gri &8 koyu gri &9 mavi &a yeşil &b turkuaz &c kırmızı &d pembe &e sarı &f beyaz
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	Stiller: &l kalın  &o italik  &n altı çizili  &k karışık  &r sıfırla
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	İkinci satır için \n kullan.    Örnek: &6&lSunucum\n&7Hoş geldin!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	Sunucu simgesi: bir görselin yolu (png/jpg/gif...) veya https:// bağlantısı.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	Otomatik olarak 64x64 piksele dönüştürülür (ortadan kare kırpılır).
Leave empty for no icon.	Simge istemiyorsan boş bırak.
File not found: {0}	Dosya bulunamadı: {0}
Server icon created (64x64)	Sunucu simgesi oluşturuldu (64x64)
Checking which popular {0} work with Minecraft {1} ...	Hangi popüler {0} Minecraft {1} ile çalışıyor kontrol ediliyor ...
[not updated for {0} yet - newest version will be tried]	[henüz {0} için güncellenmedi - en yeni sürüm denenecek]
You already added everything in the popular list. Try the search option for more.	Popüler listedeki her şeyi zaten ekledin. Daha fazlası için aramayı dene.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} çok yeni olduğundan {1} eklenti henüz güncellenmemiş olarak işaretli. Çoğu yine de çalışır; denemek istersen seç.
Pick the {0} you want (Space = tick, Enter = done, A = all)	İstediğin {0} öğelerini seç (Boşluk = işaretle, Enter = bitti, A = hepsi)
Added {0}	{0} eklendi
Add {0}  ({1} queued, loader: {2})	{0} ekle  ({1} sırada, yükleyici: {2})
Add {0}  ({1} queued)	{0} ekle  ({1} sırada)
Pick from a list of popular {0}	Popüler {0} listesinden seç
Search Modrinth for {0} (compatible with {1})	Modrinth'te {0} ara ({1} ile uyumlu)
Add direct https:// links to .jar files	.jar dosyalarına doğrudan https:// bağlantıları ekle
Show / remove queued {0}	Sıradaki {0} öğelerini göster / kaldır
Done with {0}	{0} işi bitti
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Modrinth'te ara (Minecraft {1} için {0}). Örnekler: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	Modrinth araması başarısız oldu.
Nothing found for '{0}' that works with Minecraft {1}.	'{0}' için Minecraft {1} ile çalışan bir şey bulunamadı.
Results for '{0}':	'{0}' sonuçları:
Added '{0}' (and any required dependencies).	'{0}' eklendi (ve gereken tüm bağımlılıklar).
Direct https:// links to .jar files, separated by spaces.	.jar dosyalarına doğrudan https:// bağlantıları, boşlukla ayır.
Only use links from sources you trust - these files run on your server.	Yalnızca güvendiğin kaynaklardan bağlantılar kullan - bu dosyalar sunucunda çalışır.
Skipping '{0}' (must start with https://)	'{0}' atlandı (https:// ile başlamalı)
Nothing queued yet.	Henüz sırada bir şey yok.
Back (keep everything)	Geri (hepsini koru)
Pick one to REMOVE from the install list:	Kurulum listesinden KALDIRMAK için birini seç:
Skipping invalid name '{0}'	Geçersiz ad '{0}' atlandı
Operators (admins). Minecraft usernames separated by spaces or commas.	Operatörler (yöneticiler). Minecraft kullanıcı adları, boşluk veya virgülle ayrılmış.
Ops can use all commands.	Operatörler tüm komutları kullanabilir.
Whitelist: only these players may join. Usernames separated by spaces or commas.	Beyaz liste: yalnızca bu oyuncular katılabilir. Kullanıcı adları boşluk veya virgülle ayrılmış.
Leave empty to keep the whitelist as chosen earlier.	Daha önce seçtiğin beyaz listeyi korumak için boş bırak.
Could not look up '{0}' - add later with: whitelist add {0}	'{0}' aranamadı - sonra şu komutla ekle: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	'{0}' aranamadı - sonra şu komutla ekle: op {0}
World type:	Dünya türü:
Normal terrain	Normal arazi
Superflat	Süper düz
Large biomes	Büyük biyomlar
Amplified (tall mountains)	Büyütülmüş (yüksek dağlar)
World seed (empty = random):	Dünya tohumu (boş = rastgele):
World folder name:	Dünya klasörünün adı:
Generate structures (villages, strongholds, ...)?	Yapılar oluşturulsun mu (köyler, kaleler, ...)?
Allow the Nether?	Nether'a izin verilsin mi?
Hardcore mode? (one life, forced hard difficulty)	Hardcore modu? (tek can, zorla zor seviye)
Allow player-vs-player combat (PvP)?	Oyuncuların birbiriyle savaşmasına (PvP) izin verilsin mi?
Enable command blocks?	Komut blokları etkinleştirilsin mi?
Allow flying (needed for some mods; otherwise flight is kicked)?	Uçmaya izin verilsin mi? (bazı modlar için gerekli; yoksa uçan atılır)
Spawn animals?	Hayvanlar doğsun mu?
Spawn monsters?	Canavarlar doğsun mu?
Spawn villagers?	Köylüler doğsun mu?
Force everyone into the default game mode on every join?	Her girişte herkes varsayılan oyun moduna zorlansın mı?
Spawn protection radius in blocks (0 = off):	Doğma koruma yarıçapı (blok, 0 = kapalı):
Kick idle players after N minutes (0 = never):	N dakika boşta kalan oyuncular atılsın (0 = asla):
View distance in chunks (2-32). Lower = faster:	Görüş mesafesi (chunk, 2-32). Düşük = daha hızlı:
Simulation distance in chunks (2-32). Lower = faster:	Simülasyon mesafesi (chunk, 2-32). Düşük = daha hızlı:
Please enter a number from {0} to {1}. Kept: {2}	{0} ile {1} arasında bir sayı gir. Korundu: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	Sunucu kaynak paketi: bir .zip'e doğrudan https:// bağlantısı (boş = yok).
Players are offered it when they join. Its checksum is calculated at install time.	Oyunculara katılırken önerilir. Sağlama toplamı kurulum sırasında hesaplanır.
That is not a link. Kept: {0}	Bu bir bağlantı değil. Korundu: {0}
Kick players who decline the resource pack?	Kaynak paketini reddeden oyuncular atılsın mı?
Any other server.properties setting as key=value, separated by spaces.	Diğer herhangi bir server.properties ayarı anahtar=değer biçiminde, boşlukla ayrılmış.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	Örnek: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	'{0}' atlandı (anahtar=değer kullan)
Restart the server automatically if it crashes?	Sunucu çökerse otomatik yeniden başlatılsın mı?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	Yedekleme betiği oluşturulsun mu? (dünyayı backups klasörüne sıkıştırır, en yeni 10'u tutar)
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	Mod yükleyiciler burada Velocity kurulumuyla birleştirilemez. (Paper eklentileri olur - PaperMC'yi seç.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla tek başına mod desteklemez. Bir mod yükleyici seç (düz Vanilla sunucusunun yerine geçer):
Fabric - lightweight, huge mod library (recommended)	Fabric - hafif, devasa mod kütüphanesi (önerilir)
NeoForge - big content mods (1.20.2+)	NeoForge - büyük içerik modları (1.20.2+)
Forge - classic loader (1.17+)	Forge - klasik yükleyici (1.17+)
Plain Vanilla, no mods	Düz Vanilla, modsuz
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} için Minecraft {1} sunucu sürümü yok. Başka bir yükleyici veya başka bir Minecraft sürümü seç.
Modrinth lookup failed for '{0}'.	Modrinth'te '{0}' sorgusu başarısız oldu.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	'{0}' henüz {1} için işaretli değil - en yeni sürümü ({2}) eklendi. Yine de çalışabilir.
'{0}' has no download for {1} on this loader.	'{0}' için bu yükleyicide {1} sürümüne ait indirme yok.
Newest (recommended)	En yeni (önerilir)
Type a specific older version	Belirli bir eski sürümü yaz
Which Minecraft version? (newest first)	Hangi Minecraft sürümü? (en yeni önce)
Type the exact Minecraft version (e.g. 1.20.1):	Tam Minecraft sürümünü yaz (ör. 1.20.1):
That version is not available. Pick one from the list instead.	Bu sürüm mevcut değil. Bunun yerine listeden birini seç.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	Bedrock oyuncuları (telefon, konsol, Windows 10/11) da katılabilsin mi?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	Geyser adlı ücretsiz bir eklenti üzerinden katılırlar, bu yüzden Java hesabına ihtiyaçları yok. Standart (Paper) sunucu gerekir; o senin için seçilir. Bedrock adlarının başına nokta eklenir (örneğin .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	Bedrock oyuncuları da katılabilsin mi (Geyser + Floodgate)?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	Bedrock Edition oyuncuları (telefon, konsol, Windows 10/11) Java hesabı olmadan katılabilir. PaperMC gerekir ve UDP 19132 portu açılır. Bedrock oyuncu adlarının başına nokta eklenir (örneğin .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Bedrock desteği gerektirdiği için Standart (PaperMC) sunucuya geçildi.
Downloading Geyser and Floodgate (Bedrock support) ...	Geyser ve Floodgate indiriliyor (Bedrock desteği) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Bedrock desteği kuruldu (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	telefon, konsol ve Windows 10/11 da katılabilir
Bedrock players (phones, consoles, Windows 10/11) join with:	Bedrock oyuncuları (telefon, konsol, Windows 10/11) şununla katılır:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(Minecraft Bedrock'ta: Oyna > Sunucular > Sunucu Ekle. Adlarının başına nokta eklenir, örneğin .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	İpucu: önce sunucuyu durdur (penceresine  stop  yaz). Değişiklikler başlarken okunur.
What do you want to change?	Neyi değiştirmek istiyorsun?
Server icon	Sunucu simgesi
Add plugins	Eklenti ekle
Add mods	Mod ekle
Remove plugins	Eklenti kaldır
Remove mods	Mod kaldır
Any other server.properties setting	Diğer herhangi bir server.properties ayarı
Change the Minecraft version (now {0})	Minecraft sürümünü değiştir (şimdi {0})
Bedrock players: ON (Geyser + Floodgate)	Bedrock oyuncuları: AÇIK (Geyser + Floodgate)
Bedrock players: off	Bedrock oyuncuları: kapalı
Make a backup now	Şimdi yedek al
Saved.	Kaydedildi.
All done. Start (or restart) your server to use the changes.	Hepsi tamam. Değişiklikleri kullanmak için sunucunu başlat (veya yeniden başlat).
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	Tohumu, dünya türünü veya dünya klasörü adını değiştirmek yalnızca YENİ bir dünyayı etkiler. Mevcut dünyan olduğu gibi kalır.
Backup saved: {0}	Yedek kaydedildi: {0}
Making a backup first ...	Önce yedek alınıyor ...
The backup failed - stopping here so nothing is lost.	Yedekleme başarısız oldu - hiçbir şey kaybolmasın diye burada duruyorum.
Which server do you want to change?	Hangi sunucuyu değiştirmek istiyorsun?
Pick another folder ...	Başka bir klasör seç ...
Type the folder of your server (the one that contains start-all):	Sunucunun klasörünü yaz (start-all'ın bulunduğu klasör):
That folder does not look like a server made by this tool.	Bu klasör bu araçla yapılmış bir sunucuya benzemiyor.
{0} file(s) placed in {1}	{0} dosya {1} içine yerleştirildi
Nothing is installed in this folder yet.	Bu klasörde henüz hiçbir şey kurulu değil.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	KALDIRILACAKLARI işaretle (silinmez, removed adlı bir klasöre taşınır)
Removed {0}	{0} kaldırıldı
Fetching version list ...	Sürüm listesi alınıyor ...
Could not get the version list (is the internet working?).	Sürüm listesi alınamadı (internet çalışıyor mu?).
That is the version you already have.	Bu zaten sahip olduğun sürüm.
Change Minecraft from {0} to {1}?	Minecraft {0} sürümünden {1} sürümüne geçilsin mi?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	Dünyalar eski bir sürüme geri dönemez, bu yüzden önce tam bir yedek alınır. Sonrasında eklentilerin ve modların güncellenmesi gerekebilir.
Now on Minecraft {0}	Artık Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	Bir eklenti veya mod yeni sürümde çalışmayı bırakırsa bu menüden güncelle ya da kaldır. Geri dönmek için backups klasöründeki yedeği geri yükle.
This loader has no release for that version.	Bu yükleyicinin o sürüm için bir sürümü yok.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	Bedrock desteği AÇIK. Kapatılsın mı? (Geyser ve Floodgate, removed adlı bir klasöre taşınır.)
Bedrock support turned off.	Bedrock desteği kapatıldı.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	Burada Bedrock desteği düz bir PaperMC sunucusu gerektirir (Velocity, Fabric veya Forge olmaz).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	Bedrock oyuncuları (telefon, konsol, Windows 10/11) da katılabilsin mi?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Geyser ve Floodgate eklenir. PaperMC gerektirirler. Bedrock adlarının başına nokta eklenir (örneğin .Steve). UDP {0} portu kullanılır.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	Sunucun Vanilla. PaperMC'ye geçilsin mi (aynı sürüm, aynı dünya)? Önce tam bir yedek alınır.
PaperMC has no build for this version.	PaperMC'nin bu sürüm için bir derlemesi yok.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock oyuncuları için UDP {0} portuna erişilebilmeli. playit.gg ile  bash mc-setup.sh --tunnel-guide  çalıştırıp Bedrock tünelini ekle; yönlendiricide UDP {0} portunu da yönlendir.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	Bedrock oyuncuları için UDP {0} portuna erişilebilmeli. playit.gg ile  powershell -File mc-setup.ps1 -TunnelGuide  çalıştırıp Bedrock tünelini ekle; yönlendiricide UDP {0} portunu da yönlendir.
In my home folder	Kişisel klasörümde
EOF
}
lang_data_it() { cat <<'EOF'
Let's set up your Minecraft server	Configuriamo il tuo server Minecraft
Use the arrow keys and Enter. Press Ctrl+C at any time to quit.	Usa le frecce e Invio. Premi Ctrl+C in qualsiasi momento per uscire.
Nothing is installed until you confirm at the end.	Non viene installato nulla finché non confermi alla fine.
How do you want to set up?	Come vuoi configurare?
Simple - a few easy questions, everything else is chosen for you	Semplice: poche domande facili, il resto lo sceglie lo script
Advanced - choose every option yourself	Avanzata: scegli tu ogni opzione
What do you want to call your server?	Come vuoi chiamare il tuo server?
Where should your server be saved? A new folder with your server's name is created there.	Dove salvare il server? Lì viene creata una nuova cartella con il suo nome.
Next to this script (recommended)	Accanto a questo script (consigliato)
On my Desktop	Sul Desktop
In my Documents folder	Nella cartella Documenti
Somewhere else (type a folder)	Altrove (scrivi una cartella)
Somewhere else (browse or type a folder)	Altrove (sfoglia o scrivi una cartella)
Your server will be installed in:	Il tuo server verrà installato in:
Yes, use this folder	Sì, usa questa cartella
No, pick another place	No, scegli un altro posto
Which kind of server do you want?	Che tipo di server vuoi?
Standard (recommended) - fast, and you can add plugins later	Standard (consigliato): veloce, puoi aggiungere plugin dopo
Pure Minecraft - exactly like the official game	Minecraft puro: identico al gioco ufficiale
How will your friends join?	Come entreranno i tuoi amici?
Over the internet - easiest, no router settings (free)	Via internet: il più facile, senza impostazioni del router (gratis)
Over the internet using my router (port forwarding)	Via internet con il mio router (port forwarding)
Only people on my home Wi-Fi	Solo chi è sul mio Wi-Fi di casa
Does everyone who will join own Minecraft (a paid Microsoft account)?	Tutti quelli che entreranno possiedono Minecraft (account Microsoft a pagamento)?
YES = safest, recommended.	SÌ = il più sicuro, consigliato.
NO  = anyone can join with any name (only for friends you trust).	NO = chiunque può entrare con qualsiasi nome (solo per amici fidati).
Yes	Sì
No	No
Finding the newest version ...	Cerco l'ultima versione ...
Want to change more things (server message, icon, mods, whitelist, world...)?	Vuoi cambiare altro (messaggio, icona, mod, whitelist, mondo...)?
Most people choose No - you can still do that later.	La maggior parte sceglie No; puoi farlo anche dopo.
Minecraft EULA	EULA di Minecraft
To run a server you must agree to the Minecraft End User License Agreement:	Per avviare un server devi accettare il Contratto di licenza con l'utente finale di Minecraft:
Do you agree to the EULA?	Accetti l'EULA?
Summary	Riepilogo
Install now?	Installare ora?
Installing your Minecraft server	Installo il tuo server Minecraft
Step 1 of 4 - Checking Java	Passo 1 di 4: controllo Java
Step 2 of 4 - Downloading Minecraft (this can take a minute)	Passo 2 di 4: scarico Minecraft (può volerci un minuto)
Step 3 of 4 - Setting up internet access	Passo 3 di 4: configuro l'accesso a internet
Step 4 of 4 - Finishing up	Passo 4 di 4: ultimi ritocchi
Your server is ready	Il tuo server è pronto
To start your server, run:	Per avviare il server, esegui:
To stop it, type  stop  in the server window.	Per fermarlo, scrivi  stop  nella finestra del server.
Friends join with:	Gli amici entrano con:
Note: anyone can join with any name. Only share the address with people you trust.	Nota: chiunque può entrare con qualsiasi nome. Condividi l'indirizzo solo con persone fidate.
(Your playit.gg address. Keep playit running while you play.)	(Il tuo indirizzo playit.gg. Tieni playit acceso mentre giochi.)
(Only on the same Wi-Fi.)	(Solo sullo stesso Wi-Fi.)
Start the server now?	Avviare il server ora?
All set - have fun!	Tutto pronto, buon divertimento!
Setup cancelled. Nothing was installed.	Configurazione annullata. Non è stato installato nulla.
Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)	Configurare ora il tunnel gratuito playit.gg con una guida passo passo? (circa 10 minuti, puoi farlo anche dopo)
playit.gg tunnel	Tunnel playit.gg
Name:	Nome:
Type:	Tipo:
Friends:	Amici:
Accounts:	Account:
Memory:	Memoria:
Folder:	Cartella:
Standard	Standard
Pure Minecraft	Minecraft puro
over the internet (free tunnel)	via internet (tunnel gratuito)
over the internet (router port forwarding)	via internet (port forwarding)
home Wi-Fi only	solo Wi-Fi di casa
everyone needs a Minecraft account	servono account Minecraft per tutti
anyone can join with any name	chiunque può entrare con qualsiasi nome
Press Enter to close	Premi Invio per chiudere
Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).	Non sono sicuro che questa finestra possa mostrare questa lingua. Se dopo la scelta vedi quadrati o ?, riavvia e scegli l'inglese (Windows Terminal dal Microsoft Store funziona meglio).
Use this language	Usa questa lingua
Use English instead	Usa invece l'inglese
This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?	Questo terminale non è impostato su UTF-8, quindi questa lingua potrebbe apparire rovinata (quadrati o ?). Continuare in inglese?
Use English	Usa l'inglese
Try it anyway	Prova comunque
Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.	Suggerimento: se vedi quadrati al posto delle lettere, riesegui con  -Lang en  oppure usa Windows Terminal.
Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language.	Suggerimento: se vedi quadrati al posto delle lettere, riesegui con  --lang en  oppure usa un terminale con un font compatibile.
none	nessuno
plugins	plugin
mods	mod
Back	Indietro
Customise your server. Pick a category; choose 'done' when finished.	Personalizza il tuo server. Scegli una categoria; quando hai finito scegli «fatto».
Server name: {0}	Nome del server: {0}
Server list message with colours: {0}	Messaggio nell'elenco server con colori: {0}
Server icon: {0}	Icona del server: {0}
Mods: {0} queued	Mod: {0} in coda
Plugins: {0} queued	Plugin: {0} in coda
Operators ({0}) and whitelist ({1})	Operatori ({0}) e whitelist ({1})
World type, seed, structures, nether, hardcore	Tipo di mondo, seed, strutture, Nether, hardcore
PvP, command blocks, flying, mobs, spawn protection	PvP, blocchi di comando, volo, mob, protezione spawn
View / simulation distance: {0} / {1}	Distanza di visuale / simulazione: {0} / {1}
Resource pack: {0}	Resource pack: {0}
Any other server.properties setting ({0})	Qualsiasi altra impostazione di server.properties ({0})
Auto-restart on crash, backup script	Riavvio automatico in caso di crash, script di backup
Finished customising	Termina la personalizzazione
Name of your server (e.g. Creeper Cove).	Nome del tuo server (es. Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list.	Usato per i titoli delle finestre, l'avvio automatico, i backup e, se non ne imposti uno tu, come messaggio nell'elenco server.
Server list message (MOTD).	Messaggio nell'elenco server (MOTD).
Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold	Colori: &0 nero &1 blu scuro &2 verde scuro &3 azzurro scuro &4 rosso scuro &5 viola &6 oro
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white	&7 grigio &8 grigio scuro &9 blu &a verde &b azzurro &c rosso &d rosa &e giallo &f bianco
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset	Stili: &l grassetto  &o corsivo  &n sottolineato  &k casuale  &r ripristina
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!	Usa \n per la seconda riga.    Esempio: &6&lIl Mio Server\n&7Benvenuto!
Server icon: path to an image (png/jpg/gif...) or an https:// link.	Icona del server: percorso di un'immagine (png/jpg/gif...) o link https://.
It is converted to 64x64 pixels automatically (centre-cropped to a square).	Viene convertita automaticamente a 64x64 pixel (ritagliata al centro in quadrato).
Leave empty for no icon.	Lascia vuoto per nessuna icona.
File not found: {0}	File non trovato: {0}
Server icon created (64x64)	Icona del server creata (64x64)
Checking which popular {0} work with Minecraft {1} ...	Controllo quali {0} popolari funzionano con Minecraft {1} ...
[not updated for {0} yet - newest version will be tried]	[non ancora aggiornato per {0} - verrà provata la versione più recente]
You already added everything in the popular list. Try the search option for more.	Hai già aggiunto tutto dall'elenco popolare. Prova la ricerca per trovarne altri.
Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.	Minecraft {0} è molto recente, quindi {1} plugin risultano non ancora aggiornati. Spesso funzionano comunque; sceglili se vuoi provare.
Pick the {0} you want (Space = tick, Enter = done, A = all)	Scegli i {0} che vuoi (Spazio = spunta, Invio = fatto, A = tutti)
Added {0}	{0} aggiunto
Add {0}  ({1} queued, loader: {2})	Aggiungi {0}  ({1} in coda, loader: {2})
Add {0}  ({1} queued)	Aggiungi {0}  ({1} in coda)
Pick from a list of popular {0}	Scegli da un elenco di {0} popolari
Search Modrinth for {0} (compatible with {1})	Cerca {0} su Modrinth (compatibili con {1})
Add direct https:// links to .jar files	Aggiungi link https:// diretti a file .jar
Show / remove queued {0}	Mostra / rimuovi {0} in coda
Done with {0}	Fatto con {0}
Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms	Cerca su Modrinth ({0} per Minecraft {1}). Esempi: worldedit, essentialsx, lithium, luckperms
Modrinth search failed.	Ricerca su Modrinth non riuscita.
Nothing found for '{0}' that works with Minecraft {1}.	Nessun risultato per «{0}» compatibile con Minecraft {1}.
Results for '{0}':	Risultati per «{0}»:
Added '{0}' (and any required dependencies).	«{0}» aggiunto (con le dipendenze necessarie).
Direct https:// links to .jar files, separated by spaces.	Link https:// diretti a file .jar, separati da spazi.
Only use links from sources you trust - these files run on your server.	Usa solo link di fonti affidabili: questi file vengono eseguiti sul tuo server.
Skipping '{0}' (must start with https://)	«{0}» ignorato (deve iniziare con https://)
Nothing queued yet.	Ancora nulla in coda.
Back (keep everything)	Indietro (mantieni tutto)
Pick one to REMOVE from the install list:	Scegli quello da RIMUOVERE dall'elenco di installazione:
Skipping invalid name '{0}'	Nome non valido «{0}» ignorato
Operators (admins). Minecraft usernames separated by spaces or commas.	Operatori (admin). Nomi utente Minecraft separati da spazi o virgole.
Ops can use all commands.	Gli operatori possono usare tutti i comandi.
Whitelist: only these players may join. Usernames separated by spaces or commas.	Whitelist: possono entrare solo questi giocatori. Nomi utente separati da spazi o virgole.
Leave empty to keep the whitelist as chosen earlier.	Lascia vuoto per mantenere la whitelist scelta prima.
Could not look up '{0}' - add later with: whitelist add {0}	Impossibile cercare «{0}» - aggiungilo dopo con: whitelist add {0}
Could not look up '{0}' - add later with: op {0}	Impossibile cercare «{0}» - aggiungilo dopo con: op {0}
World type:	Tipo di mondo:
Normal terrain	Terreno normale
Superflat	Superpiatto
Large biomes	Biomi grandi
Amplified (tall mountains)	Amplificato (montagne alte)
World seed (empty = random):	Seed del mondo (vuoto = casuale):
World folder name:	Nome della cartella del mondo:
Generate structures (villages, strongholds, ...)?	Generare le strutture (villaggi, fortezze, ...)?
Allow the Nether?	Consentire il Nether?
Hardcore mode? (one life, forced hard difficulty)	Modalità hardcore? (una sola vita, difficoltà difficile forzata)
Allow player-vs-player combat (PvP)?	Consentire il combattimento tra giocatori (PvP)?
Enable command blocks?	Abilitare i blocchi di comando?
Allow flying (needed for some mods; otherwise flight is kicked)?	Consentire il volo (serve per alcune mod; altrimenti chi vola viene espulso)?
Spawn animals?	Generare animali?
Spawn monsters?	Generare mostri?
Spawn villagers?	Generare abitanti?
Force everyone into the default game mode on every join?	Forzare tutti alla modalità di gioco predefinita a ogni accesso?
Spawn protection radius in blocks (0 = off):	Raggio di protezione spawn in blocchi (0 = off):
Kick idle players after N minutes (0 = never):	Espelli i giocatori inattivi dopo N minuti (0 = mai):
View distance in chunks (2-32). Lower = faster:	Distanza di visuale in chunk (2-32). Più bassa = più veloce:
Simulation distance in chunks (2-32). Lower = faster:	Distanza di simulazione in chunk (2-32). Più bassa = più veloce:
Please enter a number from {0} to {1}. Kept: {2}	Inserisci un numero da {0} a {1}. Mantenuto: {2}
Server resource pack: direct https:// link to a .zip (empty = none).	Resource pack del server: link https:// diretto a un .zip (vuoto = nessuno).
Players are offered it when they join. Its checksum is calculated at install time.	Viene proposto ai giocatori all'ingresso. Il checksum viene calcolato durante l'installazione.
That is not a link. Kept: {0}	Non è un link. Mantenuto: {0}
Kick players who decline the resource pack?	Espellere i giocatori che rifiutano il resource pack?
Any other server.properties setting as key=value, separated by spaces.	Qualsiasi altra impostazione di server.properties come chiave=valore, separate da spazi.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512	Esempio: rcon.port=25575 enable-status=true network-compression-threshold=512
Skipping '{0}' (use key=value)	«{0}» ignorato (usa chiave=valore)
Restart the server automatically if it crashes?	Riavviare automaticamente il server se va in crash?
Create a backup script (zips the world into the backups folder, keeps the newest 10)?	Creare uno script di backup (comprime il mondo nella cartella backups, tiene i 10 più recenti)?
Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)	I loader di mod non si possono combinare qui con la configurazione Velocity. (I plugin Paper sì: scegli PaperMC.)
Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):	Vanilla non supporta le mod da solo. Scegli un loader di mod (sostituisce il normale server Vanilla):
Fabric - lightweight, huge mod library (recommended)	Fabric - leggero, enorme libreria di mod (consigliato)
NeoForge - big content mods (1.20.2+)	NeoForge - mod di contenuti grandi (1.20.2+)
Forge - classic loader (1.17+)	Forge - loader classico (1.17+)
Plain Vanilla, no mods	Vanilla puro, senza mod
{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version.	{0} non ha una versione server per Minecraft {1}. Scegli un altro loader o un'altra versione di Minecraft.
Modrinth lookup failed for '{0}'.	Ricerca di «{0}» su Modrinth non riuscita.
'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work.	«{0}» non è ancora indicato per {1} - aggiunta la versione più recente ({2}). Potrebbe comunque funzionare.
'{0}' has no download for {1} on this loader.	«{0}» non ha un download per {1} con questo loader.
Newest (recommended)	La più recente (consigliata)
Type a specific older version	Digita una versione precedente specifica
Which Minecraft version? (newest first)	Quale versione di Minecraft? (la più recente per prima)
Type the exact Minecraft version (e.g. 1.20.1):	Digita la versione esatta di Minecraft (es. 1.20.1):
That version is not available. Pick one from the list instead.	Quella versione non è disponibile. Scegline una dall'elenco.
Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?	Possono unirsi anche i giocatori Bedrock (telefoni, console, Windows 10/11)?
They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve).	Entrano tramite un componente gratuito chiamato Geyser, quindi non serve un account Java. Richiede il server Standard (Paper), scelto per te. I nomi Bedrock hanno un punto davanti (per esempio .Steve).
Also let Bedrock players join (Geyser + Floodgate)?	Consentire anche ai giocatori Bedrock di unirsi (Geyser + Floodgate)?
Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve).	I giocatori di Bedrock Edition (telefoni, console, Windows 10/11) potranno unirsi senza un account Java. Serve PaperMC e viene aperta la porta UDP 19132. I nomi dei giocatori Bedrock hanno un punto davanti (per esempio .Steve).
Switched to the Standard (PaperMC) server, because Bedrock support needs it.	Passato al server Standard (PaperMC), perché il supporto Bedrock lo richiede.
Downloading Geyser and Floodgate (Bedrock support) ...	Scarico Geyser e Floodgate (supporto Bedrock) ...
Bedrock support installed (Geyser + Floodgate, UDP {0})	Supporto Bedrock installato (Geyser + Floodgate, UDP {0})
Bedrock:	Bedrock:
phones, consoles and Windows 10/11 can join too	possono unirsi anche telefoni, console e Windows 10/11
Bedrock players (phones, consoles, Windows 10/11) join with:	I giocatori Bedrock (telefoni, console, Windows 10/11) entrano con:
(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)	(In Minecraft Bedrock: Gioca > Server > Aggiungi server. I loro nomi hanno un punto davanti, come .Steve.)
Tip: stop the server first (type  stop  in its window). Changes are read when it starts.	Suggerimento: ferma prima il server (scrivi  stop  nella sua finestra). Le modifiche vengono lette all'avvio.
What do you want to change?	Cosa vuoi cambiare?
Server icon	Icona del server
Add plugins	Aggiungi plugin
Add mods	Aggiungi mod
Remove plugins	Rimuovi plugin
Remove mods	Rimuovi mod
Any other server.properties setting	Qualsiasi altra impostazione di server.properties
Change the Minecraft version (now {0})	Cambia la versione di Minecraft (ora {0})
Bedrock players: ON (Geyser + Floodgate)	Giocatori Bedrock: ATTIVO (Geyser + Floodgate)
Bedrock players: off	Giocatori Bedrock: non attivo
Make a backup now	Crea un backup adesso
Saved.	Salvato.
All done. Start (or restart) your server to use the changes.	Fatto. Avvia (o riavvia) il server per usare le modifiche.
Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.	Cambiare il seed, il tipo di mondo o il nome della cartella riguarda solo un NUOVO mondo. Il tuo mondo attuale resta com'è.
Backup saved: {0}	Backup salvato: {0}
Making a backup first ...	Prima creo un backup ...
The backup failed - stopping here so nothing is lost.	Il backup non è riuscito: mi fermo qui per non perdere nulla.
Which server do you want to change?	Quale server vuoi cambiare?
Pick another folder ...	Scegli un'altra cartella ...
Type the folder of your server (the one that contains start-all):	Digita la cartella del tuo server (quella che contiene start-all):
That folder does not look like a server made by this tool.	Quella cartella non sembra un server creato con questo strumento.
{0} file(s) placed in {1}	{0} file inseriti in {1}
Nothing is installed in this folder yet.	In questa cartella non è ancora installato nulla.
Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)	Spunta quelli da RIMUOVERE (vengono spostati in una cartella chiamata removed, non eliminati)
Removed {0}	{0} rimosso
Fetching version list ...	Recupero l'elenco delle versioni ...
Could not get the version list (is the internet working?).	Impossibile ottenere l'elenco delle versioni (Internet funziona?).
That is the version you already have.	È la versione che hai già.
Change Minecraft from {0} to {1}?	Cambiare Minecraft da {0} a {1}?
Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards.	I mondi non possono tornare a una versione precedente, quindi prima viene fatto un backup completo. Dopo potrebbe servire aggiornare plugin e mod.
Now on Minecraft {0}	Ora su Minecraft {0}
If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.	Se un plugin o una mod smette di funzionare con la nuova versione, aggiornala o rimuovila da questo menu. Per tornare indietro, ripristina il backup dalla cartella backups.
This loader has no release for that version.	Questo loader non ha una versione per quella versione.
Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)	Il supporto Bedrock è ATTIVO. Disattivarlo? (Geyser e Floodgate vengono spostati in una cartella chiamata removed.)
Bedrock support turned off.	Supporto Bedrock disattivato.
Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).	Qui il supporto Bedrock richiede un normale server PaperMC (non Velocity, Fabric o Forge).
Let Bedrock players (phones, consoles, Windows 10/11) join too?	Consentire anche ai giocatori Bedrock (telefoni, console, Windows 10/11) di unirsi?
Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used.	Vengono aggiunti Geyser e Floodgate. Richiedono PaperMC. I nomi Bedrock hanno un punto davanti (per esempio .Steve). Viene usata la porta UDP {0}.
Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.	Il tuo server è Vanilla. Passare a PaperMC (stessa versione, stesso mondo)? Prima viene fatto un backup completo.
PaperMC has no build for this version.	PaperMC non ha una build per questa versione.
Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	I giocatori Bedrock hanno bisogno che la porta UDP {0} sia raggiungibile. Con playit.gg esegui  bash mc-setup.sh --tunnel-guide  per aggiungere il tunnel Bedrock; con un router, inoltra anche la UDP {0}.
Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.	I giocatori Bedrock hanno bisogno che la porta UDP {0} sia raggiungibile. Con playit.gg esegui  powershell -File mc-setup.ps1 -TunnelGuide  per aggiungere il tunnel Bedrock; con un router, inoltra anche la UDP {0}.
In my home folder	Nella mia cartella home
EOF
}

lang_load() {   # <code>
  local code="$1" k v f
  TR=(); BOX_OPEN=0;
  [[ "$code" == "en" ]] && return 0
  while IFS=$'\t' read -r k v; do [[ -n "$k" && -n "$v" ]] && TR["$k"]="$v"; done < <("lang_data_$code" 2>/dev/null || true)
  for f in "$(dirname "${BASH_SOURCE[0]}")/lang/$code.txt" "$PWD/lang/$code.txt"; do
    [[ -f "$f" ]] && while IFS=$'\t' read -r k v; do [[ -n "$k" && -n "$v" && "$k" != \#* ]] && TR["$k"]="$v"; done <"$f"
  done
  case "$code" in zh|ja|ko|hi|ar|he) BOX_OPEN=1 ;; esac
  return 0
}
L() {   # translate a (possibly multi-line) message line by line; unknown lines stay English
  local t="$1" line out="" first=1
  if (( ${#TR[@]} == 0 )); then printf '%s' "$t"; return 0; fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "$line" && -n "${TR[$line]+x}" ]]; then
      line="${TR[$line]}"
    fi
    if (( first )); then out="$line"; first=0; else out+=$'\n'"$line"; fi
  done <<<"$t"
  printf '%s' "$out"
}
lang_from_locale() {
  local l="${MCS_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}"
  l="${l%%[._@]*}"; l="${l%%-*}"; l="${l%%_*}"; l="${l,,}"
  case "$l" in zh|en|es|fr|de|pt|ru|ja|ko|hi|ar|he|tr|it) echo "$l" ;; iw) echo he ;; *) echo en ;; esac
}

# ----------------------------------------------------------------------------
#  Look & feel: colours, symbols, banner (colour, mono and plain-ASCII fallbacks)
# ----------------------------------------------------------------------------
COLS=$(tput cols 2>/dev/null || echo 80); [[ "$COLS" =~ ^[0-9]+$ ]] || COLS=80; (( COLS < 40 )) && COLS=80
ROWS=$(tput lines 2>/dev/null || echo 24); [[ "$ROWS" =~ ^[0-9]+$ ]] || ROWS=24
FANCY=0   # 1 = arrow-key menus (needs a real terminal)
if [[ -t 0 && -t 1 && "${MCS_UI:-}" != "text" ]]; then FANCY=1; fi

C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_GREEN=""; C_ACC=""; C_GRAY=""; GRAD=()
if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_RED=$'\e[31m'; C_YELLOW=$'\e[33m'
  C_CYAN=$'\e[36m'; C_GREEN=$'\e[32m'
  if [[ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]]; then
    C_ACC=$'\e[38;5;77m'; C_GRAY=$'\e[38;5;243m'; GRAD=(22 28 34 40 76 82)
  else
    C_ACC=$'\e[32m'; C_GRAY=$'\e[90m'
  fi
fi

UTF=0
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF=1 ;; esac
if (( UTF )); then
  S_TOP="┌"; S_BAR="│"; S_END="└"; S_ACT="◆"; S_DONE="◇"; S_ON="●"; S_OFF="○"
  S_OK="✔"; S_WARN="▲"; S_ERR="■"; S_INFO="•"; S_BOXON="◼"; S_BOXOFF="◻"; B_TR="╮"; B_BL="├"; B_BR="╯"; B_H="─"
  SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); BAR_FULL="█"; BAR_EMPTY="░"
else
  S_TOP="+"; S_BAR="|"; S_END="+"; S_ACT="*"; S_DONE="o"; S_ON="(*)"; S_OFF="( )"
  S_OK="v"; S_WARN="!"; S_ERR="x"; S_INFO="-"; S_BOXON="[x]"; S_BOXOFF="[ ]"; B_TR="+"; B_BL="+"; B_BR="+"; B_H="-"
  SPIN=('|' '/' '-' '\'); BAR_FULL="#"; BAR_EMPTY="."
fi

# ----------------------------------------------------------------------------
#  Right-to-left text (Hebrew / Arabic). Most terminals that are not built for it (Windows Terminal, Terminal.app,
#  xterm ...) print characters left to right and do not reorder them. So, when VIS=1, every line that contains
#  Hebrew/Arabic is converted ONCE, in the printf below (the single place all program text is printed from), to
#  display order: words and letters reversed, English words / numbers / paths kept readable, brackets mirrored,
#  Arabic letters joined. All the program's text stays in normal (logical) order until then.
#  MCS_BIDI=1 turns it off (a terminal that reorders by itself: Konsole, mlterm, iTerm2, new GNOME Terminal);
#  MCS_BIDI=0 forces it on.
# ----------------------------------------------------------------------------
VIS=1
case "${MCS_BIDI:-auto}" in
  1) VIS=0 ;;
  0) VIS=1 ;;
  *) if [[ -n "${KONSOLE_VERSION:-}${MLTERM:-}${ITERM_SESSION_ID:-}" || "${TERM_PROGRAM:-}" == "iTerm.app" ]] \
        || { [[ "${VTE_VERSION:-0}" =~ ^[0-9]+$ ]] && (( ${VTE_VERSION:-0} >= 7600 )); }; then VIS=0; fi ;;
esac
declare -A AR_ISO=() AR_FIN=() AR_INI=() AR_MED=() AR_LIG_ISO=() AR_LIG_FIN=()
bidi_init_tables() {   # Arabic letter forms (isolated, final, initial, medial), filled once when first needed
  local e k a b c d hex kc
  if (( ${#AR_ISO[@]} )); then return 0; fi
  for e in 0621:FE80:0:0:0 0622:FE81:FE82:0:0 0623:FE83:FE84:0:0 0624:FE85:FE86:0:0 0625:FE87:FE88:0:0 0626:FE89:FE8A:FE8B:FE8C 0627:FE8D:FE8E:0:0 \
    0628:FE8F:FE90:FE91:FE92 0629:FE93:FE94:0:0 062A:FE95:FE96:FE97:FE98 062B:FE99:FE9A:FE9B:FE9C 062C:FE9D:FE9E:FE9F:FEA0 062D:FEA1:FEA2:FEA3:FEA4 \
    062E:FEA5:FEA6:FEA7:FEA8 062F:FEA9:FEAA:0:0 0630:FEAB:FEAC:0:0 0631:FEAD:FEAE:0:0 0632:FEAF:FEB0:0:0 0633:FEB1:FEB2:FEB3:FEB4 0634:FEB5:FEB6:FEB7:FEB8 \
    0635:FEB9:FEBA:FEBB:FEBC 0636:FEBD:FEBE:FEBF:FEC0 0637:FEC1:FEC2:FEC3:FEC4 0638:FEC5:FEC6:FEC7:FEC8 0639:FEC9:FECA:FECB:FECC 063A:FECD:FECE:FECF:FED0 \
    0641:FED1:FED2:FED3:FED4 0642:FED5:FED6:FED7:FED8 0643:FED9:FEDA:FEDB:FEDC 0644:FEDD:FEDE:FEDF:FEE0 0645:FEE1:FEE2:FEE3:FEE4 0646:FEE5:FEE6:FEE7:FEE8 \
    0647:FEE9:FEEA:FEEB:FEEC 0648:FEED:FEEE:0:0 0649:FEEF:FEF0:0:0 064A:FEF1:FEF2:FEF3:FEF4; do
    IFS=: read -r k a b c d <<<"$e"
    kc=$((16#$k))
    builtin printf -v hex '%08x' "$((16#$a))"; builtin printf -v "AR_ISO[$kc]" "\\U$hex"
    if [[ "$b" != "0" ]]; then builtin printf -v hex '%08x' "$((16#$b))"; builtin printf -v "AR_FIN[$kc]" "\\U$hex"; fi
    if [[ "$c" != "0" ]]; then builtin printf -v hex '%08x' "$((16#$c))"; builtin printf -v "AR_INI[$kc]" "\\U$hex"; fi
    if [[ "$d" != "0" ]]; then builtin printf -v hex '%08x' "$((16#$d))"; builtin printf -v "AR_MED[$kc]" "\\U$hex"; fi
  done
  for e in 0622:FEF5:FEF6 0623:FEF7:FEF8 0625:FEF9:FEFA 0627:FEFB:FEFC; do   # lam + alef
    IFS=: read -r k a b <<<"$e"
    kc=$((16#$k))
    builtin printf -v hex '%08x' "$((16#$a))"; builtin printf -v "AR_LIG_ISO[$kc]" "\\U$hex"
    builtin printf -v hex '%08x' "$((16#$b))"; builtin printf -v "AR_LIG_FIN[$kc]" "\\U$hex"
  done
  return 0
}
bidi_cp()  { builtin printf -v BCP '%d' "'${1:0:1}"; }
bidi_isr() {   # is codepoint $1 a right-to-left letter?
  local c=$1
  if (( c >= 0x590 && c <= 0x5FF )); then return 0; fi
  if (( c >= 0x600 && c <= 0x6FF )); then
    if (( c == 0x60C || c == 0x670 || (c >= 0x660 && c <= 0x669) || (c >= 0x610 && c <= 0x61A) || (c >= 0x64B && c <= 0x65F) || (c >= 0x6D6 && c <= 0x6ED) )); then return 1; fi
    return 0
  fi
  if (( (c >= 0x750 && c <= 0x77F) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF) )); then return 0; fi
  return 1
}
bidi_ismark() {
  local c=$1
  if (( (c >= 0x591 && c <= 0x5BD) || c == 0x5BF || c == 0x5C1 || c == 0x5C2 || c == 0x5C4 || c == 0x5C5 || c == 0x5C7 || (c >= 0x64B && c <= 0x65F) || c == 0x670 || (c >= 0x610 && c <= 0x61A) )); then return 0; fi
  return 1
}
bidi_join() {   # sets BJ: D = joins both sides, R = joins the letter before it only, U = does not join
  if [[ -n "${AR_INI[$1]+x}" ]]; then BJ=D; elif [[ -n "${AR_FIN[$1]+x}" ]]; then BJ=R; else BJ=U; fi
}
bidi_shape() {   # in: SH_IN[] (cells, logical order)  out: SH_T[] (joined forms) SH_I[] (source index)
  local n=${#SH_IN[@]} i j c pj nj g rest skip=-1 nc
  SH_T=(); SH_I=()
  for (( i=0; i<n; i++ )); do
    if (( i == skip )); then continue; fi
    bidi_cp "${SH_IN[i]}"; c=$BCP; rest="${SH_IN[i]:1}"
    bidi_join "$c"
    if [[ "$BJ" == U ]]; then SH_T+=("${SH_IN[i]}"); SH_I+=("$i"); continue; fi
    j=$((i-1)); while (( j >= 0 )); do bidi_cp "${SH_IN[j]}"; if bidi_ismark "$BCP"; then j=$((j-1)); else break; fi; done
    pj=0
    if (( j >= 0 )); then bidi_cp "${SH_IN[j]}"; bidi_join "$BCP"; if [[ "$BJ" == D ]] && bidi_isr "$BCP"; then pj=1; fi; fi
    if (( c == 0x644 && i + 1 < n )); then
      bidi_cp "${SH_IN[i+1]}"; nc=$BCP
      if [[ -n "${AR_LIG_ISO[$nc]+x}" ]]; then
        if (( pj )); then g="${AR_LIG_FIN[$nc]}"; else g="${AR_LIG_ISO[$nc]}"; fi
        SH_T+=("$g$rest${SH_IN[i+1]:1}"); SH_I+=("$i"); skip=$((i+1)); continue
      fi
    fi
    nj=0; bidi_join "$c"
    if [[ "$BJ" == D ]]; then
      j=$((i+1)); while (( j < n )); do bidi_cp "${SH_IN[j]}"; if bidi_ismark "$BCP"; then j=$((j+1)); else break; fi; done
      if (( j < n )); then bidi_cp "${SH_IN[j]}"; bidi_join "$BCP"; if [[ "$BJ" != U ]]; then nj=1; fi; fi
    fi
    g="${AR_ISO[$c]}"
    if (( pj && nj )) && [[ -n "${AR_MED[$c]+x}" ]]; then g="${AR_MED[$c]}"
    elif (( pj )) && [[ -n "${AR_FIN[$c]+x}" ]]; then g="${AR_FIN[$c]}"
    elif (( nj )) && [[ -n "${AR_INI[$c]+x}" ]]; then g="${AR_INI[$c]}"; fi
    SH_T+=("$g$rest"); SH_I+=("$i")
  done
  return 0
}
bidi_core() {   # in: BC[] (cells, logical order)  out: BO_T[] (cells, display order) BO_I[] (source index of each)
  local n=${#BC[@]} i j x c ch base="" d l r s e
  local -a K=() RS=() RE=() RD=() order=()
  BO_T=(); BO_I=()
  for (( i=0; i<n; i++ )); do
    bidi_cp "${BC[i]}"; c=$BCP; ch="${BC[i]:0:1}"
    if bidi_isr "$c"; then K[i]=R
    elif [[ "$ch" == [[:alnum:]] ]] || (( c >= 0x2E80 && !(c >= 0x3000 && c <= 0x3003) )); then K[i]=L
    else K[i]=N; fi
    if [[ -z "$base" && "${K[i]}" != N ]]; then base="${K[i]}"; fi
  done
  if [[ -z "$base" ]]; then BO_T=("${BC[@]}"); for (( i=0; i<n; i++ )); do BO_I+=("$i"); done; return 0; fi
  for (( i=0; i<n; i++ )); do   # % $ etc. stick to a neighbouring number
    if [[ "${K[i]}" == N && "${BC[i]}" == [%\$€£¢°#] ]]; then
      if { (( i > 0 )) && [[ "${BC[i-1]:0:1}" == [[:digit:]] ]]; } || { (( i + 1 < n )) && [[ "${BC[i+1]:0:1}" == [[:digit:]] ]]; }; then K[i]=L; fi
    fi
  done
  for (( i=0; i<n; i++ )); do   # command-line flags such as -Lang / --lang stay together
    if [[ "${BC[i]}" == "-" && "${K[i]}" == N ]] && { (( i == 0 )) || [[ "${BC[i-1]}" == " " || "${BC[i-1]}" == "-" ]]; } && (( i + 1 < n )) && [[ "${BC[i+1]}" == "-" || "${BC[i+1]}" == [A-Za-z] ]]; then K[i]=L; fi
  done
  i=0
  while (( i < n )); do   # neutrals take the direction of both neighbours when they agree, otherwise the paragraph direction
    if [[ "${K[i]}" != N ]]; then i=$((i+1)); continue; fi
    j=$i; while (( j < n )) && [[ "${K[j]}" == N ]]; do j=$((j+1)); done
    l=$base; if (( i > 0 )); then l="${K[i-1]}"; fi
    r=$base; if (( j < n )); then r="${K[j]}"; fi
    d=$base; if [[ "$l" == "$r" ]]; then d=$l; fi
    for (( x=i; x<j; x++ )); do K[x]=$d; done
    i=$j
  done
  i=0
  while (( i < n )); do
    j=$i; while (( j < n )) && [[ "${K[j]}" == "${K[i]}" ]]; do j=$((j+1)); done
    RS+=("$i"); RE+=("$j"); RD+=("${K[i]}"); i=$j
  done
  local nr=${#RS[@]}
  for (( x=0; x<nr; x++ )); do if [[ "$base" == R ]]; then order+=("$((nr-1-x))"); else order+=("$x"); fi; done
  local rr
  for rr in "${order[@]}"; do
    s=${RS[rr]}; e=${RE[rr]}
    if [[ "${RD[rr]}" == R ]]; then
      bidi_init_tables
      SH_IN=("${BC[@]:s:e-s}")
      bidi_shape
      for (( x=${#SH_T[@]}-1; x>=0; x-- )); do
        ch="${SH_T[x]}"
        case "$ch" in "(") ch=")" ;; ")") ch="(" ;; "[") ch="]" ;; "]") ch="[" ;; "{") ch="}" ;; "}") ch="{" ;; "<") ch=">" ;; ">") ch="<" ;; esac
        BO_T+=("$ch"); BO_I+=("$(( s + SH_I[x] ))")
      done
    else
      for (( x=s; x<e; x++ )); do BO_T+=("${BC[x]}"); BO_I+=("$x"); done
    fi
  done
  return 0
}
bidi_visual() {   # <plain text, no colour codes> -> BV (display order)
  local s="$1" ch cp tail=0
  local -a cells=()
  BV="$s"
  has_rtl "$s" || return 0
  local i n=${#s}
  for (( i=0; i<n; i++ )); do
    ch="${s:i:1}"; builtin printf -v cp '%d' "'$ch"
    if (( ${#cells[@]} )) && bidi_ismark "$cp"; then cells[${#cells[@]}-1]+="$ch"; else cells+=("$ch"); fi
  done
  while (( ${#cells[@]} )) && [[ "${cells[${#cells[@]}-1]}" == " " ]]; do unset 'cells[${#cells[@]}-1]'; tail=$((tail+1)); done
  BC=("${cells[@]}"); bidi_core
  BV=""; for ch in "${BO_T[@]}"; do BV+="$ch"; done
  for (( i=0; i<tail; i++ )); do BV+=" "; done
  return 0
}
has_rtl() { local LC_ALL=C; [[ "$1" == *[$'\xd6'-$'\xdb\xdd\xef']* ]]; }   # cheap byte test: could this hold Hebrew/Arabic?
bidi_emit() {   # in: ET_T[] ET_S[] (text, colour) -> EM
  local x last="" st
  EM=""
  for (( x=0; x<${#ET_T[@]}; x++ )); do
    st="${ET_S[x]}"
    if [[ "$st" != "$last" ]]; then if [[ -n "$last" ]]; then EM+=$'\e[0m'; fi; EM+="$st"; last="$st"; fi
    EM+="${ET_T[x]}"
  done
  if [[ -n "$last" ]]; then EM+=$'\e[0m'; fi
  return 0
}
# One printed line that may contain colour codes: keep the leading symbols (bar, bullet, "1)") on the left, wrap long
# text, convert each piece, keep the colours attached to their letters.   -> VL
vis_line() {
  local line="$1" n=${#1} i=0 ch seq p cp pre="" suf="" cur="" seen=0 c0=0 j end s0 e0 b room pe x pi out="" headFirst="" headNext="" tailsp k
  local -a C=() S=() PS=() PE=()
  local chrome='│┌└◆◇●○✔▲■•◼◻╭╮├╯─ '
  VL="$line"
  has_rtl "$line" || return 0
  while (( i < n )); do
    ch="${line:i:1}"; i=$((i+1))
    if [[ "$ch" == $'\e' ]]; then
      seq="$ch"
      while (( i < n )); do ch="${line:i:1}"; seq+="$ch"; i=$((i+1)); if [[ "$ch" == [A-Za-z] ]]; then break; fi; done
      if [[ "$seq" == *m ]]; then p="${seq:2:${#seq}-3}"; if [[ -z "$p" || "$p" == 0 ]]; then cur=""; else cur+="$seq"; fi
      elif (( seen )); then suf+="$seq"; else pre+="$seq"; fi
    elif [[ "$ch" == $'\r' ]]; then if (( seen )); then suf+="$ch"; else pre+="$ch"; fi
    else
      builtin printf -v cp '%d' "'$ch"
      if (( ${#C[@]} )) && bidi_ismark "$cp"; then C[${#C[@]}-1]+="$ch"; else C+=("$ch"); S+=("$cur"); seen=1; fi
    fi
  done
  n=${#C[@]}
  while (( c0 < n )); do
    ch="${C[c0]}"
    if [[ ${#ch} -eq 1 && "$chrome" == *"$ch"* ]]; then c0=$((c0+1)); continue; fi
    if [[ "$ch" == [0-9] ]]; then
      j=$c0; while (( j < n )) && [[ "${C[j]}" == [0-9] ]]; do j=$((j+1)); done
      if (( j < n )) && [[ "${C[j]}" == ")" ]]; then c0=$((j+1)); continue; fi
    fi
    break
  done
  end=$n; while (( end > c0 )) && [[ "${C[end-1]}" == " " ]]; do end=$((end-1)); done
  room=$(( ${COLS:-80} - 2 - c0 )); if (( room < 20 )); then room=20; fi
  s0=$c0
  while (( s0 < end )); do
    e0=$(( s0 + room )); if (( e0 > end )); then e0=$end; fi
    if (( e0 < end )); then b=$e0; while (( b > s0 + 1 )) && [[ "${C[b-1]}" != " " ]]; do b=$((b-1)); done; if (( b > s0 + 1 )); then e0=$b; fi; fi
    PS+=("$s0"); PE+=("$e0"); s0=$e0
    while (( s0 < end )) && [[ "${C[s0]}" == " " ]]; do s0=$((s0+1)); done
  done
  if (( ${#PS[@]} == 0 )); then return 0; fi
  if (( c0 > 0 )); then
    ET_T=("${C[@]:0:c0}"); ET_S=("${S[@]:0:c0}"); bidi_emit; headFirst="$EM"
    headNext="${S[0]}│"; if [[ -n "${S[0]}" ]]; then headNext+=$'\e[0m'; fi
    for (( k=1; k<c0; k++ )); do headNext+=" "; done
  fi
  for (( pi=0; pi<${#PS[@]}; pi++ )); do
    pe=${PE[pi]}; while (( pe > PS[pi] + 1 )) && [[ "${C[pe-1]}" == " " ]]; do pe=$((pe-1)); done
    BC=("${C[@]:PS[pi]:pe-PS[pi]}"); bidi_core
    ET_T=("${BO_T[@]}"); ET_S=(); for x in "${BO_I[@]}"; do ET_S+=("${S[PS[pi]+x]}"); done
    bidi_emit
    tailsp=""; if (( pi == ${#PS[@]} - 1 && end < n )); then for (( k=0; k<n-end; k++ )); do tailsp+=" "; done; fi
    if (( pi == 0 )); then out+="$headFirst$EM$tailsp"; else out+=$'\n'"$headNext$EM$tailsp"; fi
  done
  VL="$pre$out$suf"
  return 0
}
vis_text() {   # <text, possibly several lines> -> VIS_OUT
  local rest="$1" line out=""
  while [[ "$rest" == *$'\n'* ]]; do
    line="${rest%%$'\n'*}"; rest="${rest#*$'\n'}"
    vis_line "$line"; out+="$VL"$'\n'
  done
  vis_line "$rest"; VIS_OUT="$out$VL"
  return 0
}
if (( ! UTF )); then VIS=0; fi   # without a UTF-8 terminal there is nothing to reorder
if (( VIS )); then
  printf() {   # everything the program shows on the terminal goes through here (answers captured with $(...) do not)
    if [[ "${1:-}" == "-v" ]] || ! [[ -t 1 ]]; then builtin printf "$@"; return; fi
    local _o
    builtin printf -v _o "$@"
    if has_rtl "$_o"; then vis_text "$_o"; _o="$VIS_OUT"; fi
    builtin printf '%s' "$_o"
  }
fi

cp_width() {   # terminal cells for codepoint $1 -> CW (2 for Chinese/Japanese/Korean, 0 for combining marks)
  local c=$1; CW=1
  if (( c < 0x300 )); then return 0; fi
  if (( (c >= 0x300 && c <= 0x36F) || (c >= 0x900 && c <= 0x902) || c == 0x93C || (c >= 0x941 && c <= 0x948) || c == 0x94D || (c >= 0x951 && c <= 0x957) || c == 0x962 || c == 0x963 || c == 0x200B || c == 0x200D )) || bidi_ismark "$c"; then CW=0; return 0; fi
  if (( c >= 0x1100 && (c <= 0x115F || (c >= 0x2E80 && c <= 0xA4CF && c != 0x303F) || (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFE30 && c <= 0xFE6F) || (c >= 0xFF00 && c <= 0xFF60) || (c >= 0xFFE0 && c <= 0xFFE6) || (c >= 0x1F300 && c <= 0x1F64F) || (c >= 0x1F900 && c <= 0x1F9FF) || (c >= 0x20000 && c <= 0x3FFFD)) )); then CW=2; fi
  return 0
}
wrap_cols() {   # <width>   (stdin lines -> stdout wrapped lines; by display width, at spaces, or between characters for Chinese/Japanese)
  local w=$1 line ch cp i n cur cw lastsp wd k rest rc
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:print:]]*$ && "$line" != *[$'\x80'-$'\xff']* ]] && (( ${#line} <= w )); then printf '%s\n' "$line"; continue; fi
    n=${#line}; cur=""; cw=0; lastsp=-1
    for (( i=0; i<n; i++ )); do
      ch="${line:i:1}"; builtin printf -v cp '%d' "'$ch"; cp_width "$cp"; wd=$CW
      if (( cw + wd > w && ${#cur} > 0 )); then
        if (( lastsp > 0 )); then
          rest="${cur:lastsp+1}"; cur="${cur:0:lastsp}"; cur="${cur%"${cur##*[! ]}"}"
          builtin printf '%s\n' "$cur"; cur="$rest"; cw=0
          for (( k=0; k<${#cur}; k++ )); do builtin printf -v rc '%d' "'${cur:k:1}"; cp_width "$rc"; cw=$((cw+CW)); done
        else builtin printf '%s\n' "$cur"; cur=""; cw=0; fi
        lastsp=-1
      fi
      if [[ "$ch" == " " ]]; then if [[ -z "$cur" ]]; then continue; fi; lastsp=${#cur}; fi
      cur+="$ch"; cw=$((cw+wd))
    done
    if [[ -n "$cur" ]]; then builtin printf '%s\n' "$cur"; fi
  done
  return 0
}

# One line of the timeline:  "|  text"
say()      { printf '%s%s%s  %s\n' "$C_GRAY" "$S_BAR" "$C_RESET" "$*" >&2; }
bar_line() { printf '%s%s%s\n' "$C_GRAY" "$S_BAR" "$C_RESET" >&2; }
info()  { say "${C_CYAN}${S_INFO}${C_RESET} $(L "$*")"; }
ok()    { say "${C_GREEN}${S_OK}${C_RESET} $(L "$*")"; }
warn()  { say "${C_YELLOW}${S_WARN}${C_RESET} $(L "$*")"; }
step()  { bar_line; printf '%s%s%s  %s%s%s\n' "$C_GREEN" "$S_DONE" "$C_RESET" "$C_BOLD" "$(L "$*")" "$C_RESET" >&2; }
cursor_hide() { if (( FANCY )); then printf '\e[?25l' >&2; fi; return 0; }
cursor_show() { if (( FANCY )); then printf '\e[?25h' >&2; fi; return 0; }

banner() {
  local art=(
'███╗   ███╗██╗███╗   ██╗███████╗ ██████╗██████╗  █████╗ ███████╗████████╗'
'████╗ ████║██║████╗  ██║██╔════╝██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝'
'██╔████╔██║██║██╔██╗ ██║█████╗  ██║     ██████╔╝███████║█████╗     ██║   '
'██║╚██╔╝██║██║██║╚██╗██║██╔══╝  ██║     ██╔══██╗██╔══██║██╔══╝     ██║   '
'██║ ╚═╝ ██║██║██║ ╚████║███████╗╚██████╗██║  ██║██║  ██║██║        ██║   '
'╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   ')
  local i=0 l
  printf '\n' >&2
  if (( UTF && COLS >= 76 )); then
    for l in "${art[@]}"; do
      if (( ${#GRAD[@]} )); then printf '\e[38;5;%sm%s\e[0m\n' "${GRAD[i]}" "$l" >&2
      else printf '%s%s%s\n' "$C_ACC" "$l" "$C_RESET" >&2; fi
      i=$((i+1))
    done
    printf '%s%s%s\n' "$C_GRAY" '        S E R V E R   S E T U P   W I Z A R D' "$C_RESET" >&2
  else
    printf '%s%s%s\n' "$C_ACC$C_BOLD" '  M I N E C R A F T   S E R V E R   S E T U P' "$C_RESET" >&2
  fi
  printf '\n' >&2
}

MAIN_PID=$$
STATE_DIR=$(mktemp -d)
cleanup() { cursor_show; rm -rf "$STATE_DIR"; }
trap cleanup EXIT
cancel_msg() { cursor_show; printf '\n%s%s%s  %s\n' "$C_YELLOW" "$S_END" "$C_RESET" "$(L "Setup cancelled. Nothing was installed.")" >&2; }
# die/cancel may run inside $(...) subshells, so they signal the main script too
die() {
  cursor_show
  printf '%s%s%s  %s%s%s\n%s%s%s\n' "$C_RED" "$S_ERR" "$C_RESET" "$C_RED" "$*" "$C_RESET" "$C_RED" "$S_END" "$C_RESET" >&2
  touch "$STATE_DIR/died"
  [[ "$BASHPID" != "$MAIN_PID" ]] && kill -USR2 "$MAIN_PID" 2>/dev/null
  exit 1
}
trap 'exit 1' USR2
trap 'cancel_msg; exit 0' USR1
trap 'cancel_msg; exit 130' INT
trap '[[ -f "$STATE_DIR/died" ]] && exit 1; die "Something went wrong on line $LINENO (command: $BASH_COMMAND)."' ERR

usage() {
  cat <<EOF
mc-setup.sh v${SCRIPT_VERSION} - interactive Minecraft server installer

  bash mc-setup.sh          Run the setup wizard
  bash mc-setup.sh --lang de   Pick the language (en es fr de pt ru zh ja ko hi ar he tr it)
  bash mc-setup.sh --tunnel-guide   Step-by-step playit.gg tunnel guide (for an existing server)
  MCS_UI=text bash ...      Use plain numbered prompts instead of arrow-key menus
  MCS_BIDI=1 bash ...       Hebrew/Arabic: leave text alone (terminal already shows right-to-left correctly)
  MCS_BIDI=0 bash ...       Hebrew/Arabic: always convert to display order
  NO_COLOR=1 bash ...       Turn colours off

Requires: Linux or macOS (Intel or Apple Silicon / ARM64), bash 4.3+, curl, jq
(installed automatically when a package manager is available). Run as a normal user.
On a Mac, double-click mc-setup.command: it installs a newer bash if needed.
EOF
}
_args=()
while (( $# )); do
  case "$1" in --lang) MCS_LANG="${2:-en}"; shift 2 || shift ;; *) _args+=("$1"); shift ;; esac
done
set -- ${_args[@]+"${_args[@]}"}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

# ----------------------------------------------------------------------------
#  System helpers
# ----------------------------------------------------------------------------
SUDO=""
if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

PKG=""
for p in apt-get dnf yum pacman zypper apk brew; do
  if command -v "$p" >/dev/null 2>&1; then PKG="$p"; break; fi
done

pkg_install() {   # pkg_install <generic-name>...
  [[ -z "$PKG" ]] && return 1
  [[ "$PKG" != "brew" && $EUID -ne 0 && -z "$SUDO" ]] && return 1
  local names=() n
  for n in "$@"; do
    case "$n:$PKG" in
      whiptail:apt-get) names+=(whiptail) ;;
      whiptail:dnf|whiptail:yum) names+=(newt) ;;
      whiptail:pacman) names+=(libnewt) ;;
      whiptail:zypper) names+=(newt) ;;
      whiptail:apk) names+=(newt) ;;
      *) names+=("$n") ;;
    esac
  done
  info "Installing: ${names[*]} (via $PKG, may ask for your password)"
  case "$PKG" in
    apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y -qq "${names[@]}" ;;
    dnf|yum) $SUDO "$PKG" install -y -q "${names[@]}" ;;
    pacman)  $SUDO pacman -S --noconfirm --needed "${names[@]}" ;;
    zypper)  $SUDO zypper -q install -y "${names[@]}" ;;
    apk)     $SUDO apk add -q "${names[@]}" ;;
    brew)    brew install "${names[@]}" ;;   # Homebrew must not run as root, so no sudo
  esac
}

# --- small portability helpers (GNU/Linux and macOS/BSD tools differ) ---------
file_size()  { wc -c <"$1" 2>/dev/null | tr -d ' ' || echo 0; }
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
hash_file()  { # hash_file <sha1|sha256> <file>
  if command -v "${1}sum" >/dev/null 2>&1; then "${1}sum" "$2" | awk '{print $1}'
  else shasum -a "${1#sha}" "$2" | awk '{print $1}'; fi
}
sedi() { if (( IS_MAC )); then sed -i '' "$@"; else sed -i "$@"; fi; }   # in-place edit
mem_mb() {
  if (( IS_MAC )); then echo $(( $(sysctl -n hw.memsize 2>/dev/null || echo 4294967296) / 1048576 ))
  else awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 4096; fi
}

pkg_hint() {   # the command a person would type to install <package> on this system
  local s="sudo "; [[ $EUID -eq 0 ]] && s=""
  case "${PKG:-}" in
    apt-get) echo "${s}apt install $*" ;;
    dnf|yum) echo "${s}${PKG} install $*" ;;
    pacman)  echo "${s}pacman -S $*" ;;
    zypper)  echo "${s}zypper install $*" ;;
    apk)     echo "${s}apk add $*" ;;
    brew)    echo "brew install $*" ;;
    *)       echo "use your system's package manager to install $*" ;;
  esac
}
need_cmd() {   # need_cmd <command> [package]
  command -v "$1" >/dev/null 2>&1 && return 0
  warn "'$1' is not installed."
  pkg_install "${2:-$1}" || true
  if ! command -v "$1" >/dev/null 2>&1 && (( IS_MAC )) && [[ "$1" == "jq" ]]; then   # no Homebrew: fetch the official single-file jq
    mkdir -p "$HOME/.mc-setup/bin"
    local a="amd64"; [[ "$(uname -m)" == "arm64" ]] && a="arm64"
    info "Downloading jq (a small helper tool) ..."
    curl -fsSL --retry 3 -o "$HOME/.mc-setup/bin/jq" "https://github.com/jqlang/jq/releases/latest/download/jq-macos-$a" \
      && chmod +x "$HOME/.mc-setup/bin/jq" || true
  fi
  command -v "$1" >/dev/null 2>&1 || die "Please install '$1' ($(pkg_hint "${2:-$1}")) and run the script again."
}

fetch() {      # fetch <url>  -> stdout
  curl -fsSL --retry 3 --connect-timeout 15 -A "$UA" "$1"
}
fmt_mb() { awk -v b="$1" 'BEGIN{printf "%.1f MB", b/1048576}'; }
download() {   # download <url> <dest>   (progress bar on a real terminal)
  local url="$1" dest="$2" name total=0 pid cur=0 pct filled i bar width=24 f=0
  name=$(basename "$dest")
  if (( FANCY )); then
    total=$(curl -fsSIL -A "$UA" "$url" 2>/dev/null | tr -d '\r' | awk 'tolower($1)=="content-length:"{v=$2} END{print v+0}')
    curl -fsSL --retry 3 --connect-timeout 15 -A "$UA" -o "$dest.part" "$url" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
      cur=$(file_size "$dest.part")
      if (( total > 0 )); then
        pct=$(( cur * 100 / total )); (( pct > 100 )) && pct=100
        filled=$(( pct * width / 100 )); bar=""
        for (( i=0; i<width; i++ )); do if (( i < filled )); then bar+="$BAR_FULL"; else bar+="$BAR_EMPTY"; fi; done
        printf '\r\e[K%s%s%s  %s%s%s  %s%s%s %3d%%  %s / %s' "$C_GRAY" "$S_BAR" "$C_RESET" "$C_DIM" "$name" "$C_RESET" "$C_ACC" "$bar" "$C_RESET" "$pct" "$(fmt_mb "$cur")" "$(fmt_mb "$total")" >&2
      else
        printf '\r\e[K%s%s%s  %s%s%s %s  %s' "$C_GRAY" "$S_BAR" "$C_RESET" "$C_ACC" "${SPIN[f % ${#SPIN[@]}]}" "$C_RESET" "$name" "$(fmt_mb "$cur")" >&2
        f=$((f+1))
      fi
      sleep 0.1
    done
    printf '\r\e[K' >&2
    if ! wait "$pid"; then die "Download failed: $name"; fi
    mv -f "$dest.part" "$dest"
    ok "$name ($(fmt_mb "$(file_size "$dest")"))"
  else
    info "Downloading $name ..."
    curl -fsSL --retry 3 --connect-timeout 15 -A "$UA" -o "$dest.part" "$url" || die "Download failed: $name"
    mv -f "$dest.part" "$dest"
  fi
}
spin_run() {   # spin_run "label" command...   (spinner while a long command runs)
  local label="$1" pid f=0; shift
  "$@" >/dev/null 2>&1 &
  pid=$!
  if (( FANCY )); then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r\e[K%s%s%s  %s%s%s %s' "$C_GRAY" "$S_BAR" "$C_RESET" "$C_ACC" "${SPIN[f % ${#SPIN[@]}]}" "$C_RESET" "$label" >&2
      f=$((f+1)); sleep 0.1
    done
    printf '\r\e[K' >&2
  else info "$label ..."; fi
  wait "$pid"
}
verify_hash() { # verify_hash <file> <sha1|sha256> <expected>
  [[ -z "${3:-}" || "${3:-}" == "null" ]] && return 0
  local got
  got=$(hash_file "$2" "$1")
  [[ "$got" == "$3" ]] || die "Checksum mismatch for $1 (expected $3, got $got)."
  ok "Checksum OK ($2)"
}

ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
  x86_64|amd64)   ARCH_JDK="x64";       ARCH_NGROK="amd64" ;;
  aarch64|arm64)  ARCH_JDK="aarch64"; ARCH_NGROK="arm64" ;;
  armv7l|armv7*)  ARCH_JDK="arm";       ARCH_NGROK="arm" ;;
  *)              ARCH_JDK="";               ARCH_NGROK="" ;;
esac
if (( IS_MAC )); then OS_JDK="mac"; OS_NGROK="darwin"; else OS_JDK="linux"; OS_NGROK="linux"; fi

ver_ge() {   # $1 >= $2, comparing dotted numbers (pure bash: macOS sort has no reliable -V)
  local -a a b; local i x y
  IFS=. read -ra a <<<"$1"; IFS=. read -ra b <<<"$2"
  for (( i=0; i < ${#a[@]} || i < ${#b[@]}; i++ )); do
    x="${a[i]:-0}"; y="${b[i]:-0}"
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"; x="${x:-0}"; y="${y:-0}"
    (( 10#$x > 10#$y )) && return 0
    (( 10#$x < 10#$y )) && return 1
  done
  return 0
}

# ----------------------------------------------------------------------------
#  UI layer: arrow-key menus in a vertical "timeline" (falls back to numbered
#  prompts when there is no real terminal or MCS_UI=text). Questions are shown
#  on stderr; the chosen answer is printed on stdout.
# ----------------------------------------------------------------------------
cancelled() {
  touch "$STATE_DIR/died"
  if [[ "$BASHPID" != "$MAIN_PID" ]]; then kill -USR1 "$MAIN_PID"; exit 0; fi
  cancel_msg; exit 0
}

_wrap() { builtin printf '%s\n' "$(L "$1")" | wrap_cols "$(( COLS - 8 ))"; }

# Finished question:  "o  Title" / "|  answer" / "|"
_done_block() {   # <title first line> <answer>
  printf '%s%s%s  %s\n' "$C_GREEN" "$S_DONE" "$C_RESET" "$1" >&2
  printf '%s%s%s  %s%s%s\n' "$C_GRAY" "$S_BAR" "$C_RESET" "$C_DIM" "$2" "$C_RESET" >&2
  bar_line
}

# ui_msg "text": plain note on the timeline
ui_msg() {
  local l
  while IFS= read -r l; do say "$l"; done < <(_wrap "$1")
  bar_line
}

# ui_box "Title" "body": rounded box. A line starting with ">>" is highlighted.
ui_box() {
  local title body="$2" lines=() l w=0 plain pad hbar i
  local raw wl
  title=$(L "$1"); body=$(L "$body")
  while IFS= read -r raw; do
    if [[ "$raw" == ">>"* ]]; then
      raw="${raw#>>}"; raw="${raw# }"
      while IFS= read -r wl; do lines+=(">> $wl"); done < <(builtin printf '%s\n' "$raw" | wrap_cols "$(( COLS - 12 ))")
    else
      while IFS= read -r wl; do lines+=("$wl"); done < <(builtin printf '%s\n' "$raw" | wrap_cols "$(( COLS - 12 ))")
    fi
  done <<<"$body"
  for l in "${lines[@]}"; do
    plain="$l"; [[ "$l" == ">>"* ]] && { plain="${l#>>}"; plain="${plain# }"; }
    (( ${#plain} > w )) && w=${#plain}
  done
  (( ${#title} > w )) && w=${#title}
  if (( BOX_OPEN )); then   # wide / combining scripts: no right edge, so nothing can look misaligned
    printf '%s%s%s  %s%s%s\n' "$C_GREEN" "$S_DONE" "$C_RESET" "$C_BOLD" "$title" "$C_RESET" >&2
    printf '%s%s%s\n' "$C_GRAY" "$S_BAR" "$C_RESET" >&2
    for l in "${lines[@]}"; do
      if [[ "$l" == ">>"* ]]; then plain="${l#>>}"; plain="${plain# }"; printf '%s%s%s  %s%s%s\n' "$C_GRAY" "$S_BAR" "$C_RESET" "$C_BOLD$C_ACC" "$plain" "$C_RESET" >&2
      else printf '%s%s%s  %s\n' "$C_GRAY" "$S_BAR" "$C_RESET" "$l" >&2; fi
    done
    printf '%s%s%s\n' "$C_GRAY" "$B_BL" "$C_RESET" >&2
    bar_line; return 0
  fi
  hbar=""; for (( i=0; i<w+4; i++ )); do hbar+="$B_H"; done
  printf '%s%s%s  %s%s%s %s%s%s\n' "$C_GREEN" "$S_DONE" "$C_RESET" "$C_BOLD" "$title" "$C_RESET" \
    "$C_GRAY" "${hbar:0:$(( w + 1 - ${#title} ))}$B_TR" "$C_RESET" >&2
  printf '%s%s%*s%s%s\n' "$C_GRAY" "$S_BAR" $(( w + 4 )) "" "$S_BAR" "$C_RESET" >&2
  for l in "${lines[@]}"; do
    if [[ "$l" == ">>"* ]]; then plain="${l#>>}"; plain="${plain# }"; pad=$(( w - ${#plain} ))
      printf '%s%s%s  %s%s%s%*s  %s%s%s\n' "$C_GRAY" "$S_BAR" "$C_RESET" "$C_BOLD$C_ACC" "$plain" "$C_RESET" "$pad" "" "$C_GRAY" "$S_BAR" "$C_RESET" >&2
    else pad=$(( w - ${#l} ))
      printf '%s%s%s  %s%*s  %s%s%s\n' "$C_GRAY" "$S_BAR" "$C_RESET" "$l" "$pad" "" "$C_GRAY" "$S_BAR" "$C_RESET" >&2
    fi
  done
  printf '%s%s%*s%s%s\n' "$C_GRAY" "$S_BAR" $(( w + 4 )) "" "$S_BAR" "$C_RESET" >&2
  printf '%s%s%s%s%s\n' "$C_GRAY" "$B_BL" "${hbar}" "$B_BR" "$C_RESET" >&2
  bar_line
}

# ui_menu "question" "default-tag" tag1 label1 tag2 label2 ...  -> echo chosen tag
ui_menu() {
  local text="$1" def="$2"; shift 2
  local tags=() labels=() hints=() n=0 sel=0 d i li tl=() choice=""
  while (( $# >= 2 )); do
    tags+=("$1"); d="$2"
    if [[ -z "$d" || "$d" == "latest" ]]; then labels+=("$1"); hints+=("$d"); else labels+=("$(L "$d")"); hints+=(""); fi
    [[ "$1" == "$def" ]] && sel=$n
    n=$((n+1)); shift 2
  done
  mapfile -t tl < <(_wrap "$text")

  if (( FANCY )); then
    local vis=$(( ROWS - ${#tl[@]} - 5 )) top=0 drawn=0 key k2 more=0
    (( vis > 12 )) && vis=12; (( vis < 3 )) && vis=3; (( vis > n )) && vis=n
    (( vis < n )) && more=1
    cursor_hide
    while true; do
      (( sel < top )) && top=$sel
      (( sel >= top + vis )) && top=$(( sel - vis + 1 ))
      (( drawn )) && printf '\e[%dA\r\e[J' "$drawn" >&2
      printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_ACT" "$C_RESET" "$C_BOLD" "${tl[0]}" "$C_RESET" >&2
      for (( li=1; li<${#tl[@]}; li++ )); do
        printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$C_DIM" "${tl[li]}" "$C_RESET" >&2
      done
      for (( i=top; i<top+vis; i++ )); do
        if (( i == sel )); then
          printf '%s%s%s  %s%s%s %s%s%s %s%s%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$C_ACC" "$S_ON" "$C_RESET" "$C_BOLD" "${labels[i]}" "$C_RESET" "$C_DIM" "${hints[i]}" "$C_RESET" >&2
        else
          printf '%s%s%s  %s%s %s %s%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$C_DIM" "$S_OFF" "${labels[i]}" "${hints[i]}" "$C_RESET" >&2
        fi
      done
      (( more )) && printf '%s%s%s  %s%d/%d  (up/down to see more)%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$C_DIM" $(( sel + 1 )) "$n" "$C_RESET" >&2
      printf '%s%s%s\n' "$C_ACC" "$S_END" "$C_RESET" >&2
      drawn=$(( ${#tl[@]} + vis + more + 1 ))
      IFS= read -rsn1 key || { cursor_show; cancelled; }
      if [[ "$key" == $'\e' ]]; then IFS= read -rsn2 -t 0.2 k2 || true; key+="$k2"; fi
      case "$key" in
        $'\e[A'|$'\eOA'|k) (( sel > 0 )) && sel=$(( sel - 1 )) || sel=$(( n - 1 )) ;;
        $'\e[B'|$'\eOB'|j) (( sel < n - 1 )) && sel=$(( sel + 1 )) || sel=0 ;;
        $'\e[H') sel=0 ;;
        $'\e[F') sel=$(( n - 1 )) ;;
        '') break ;;
      esac
    done
    printf '\e[%dA\r\e[J' "$drawn" >&2
    cursor_show
    _done_block "${tl[0]}" "${labels[sel]}"
    choice="${tags[sel]}"
  else
    local a defnum=$(( sel + 1 )) t
    printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_ACT" "$C_RESET" "$C_BOLD" "${tl[0]}" "$C_RESET" >&2
    for (( li=1; li<${#tl[@]}; li++ )); do say "${C_DIM}${tl[li]}${C_RESET}"; done
    for (( i=0; i<n; i++ )); do printf '%s%s%s  %2d) %s %s\n' "$C_GRAY" "$S_BAR" "$C_RESET" $(( i + 1 )) "${labels[i]}" "${hints[i]}" >&2; done
    while true; do
      printf '%s%s%s  Choose [%s]: ' "$C_GRAY" "$S_BAR" "$C_RESET" "$defnum" >&2
      IFS= read -r a || cancelled
      [[ -z "$a" ]] && a=$defnum
      if [[ "$a" =~ ^[0-9]+$ ]] && (( a >= 1 && a <= n )); then choice="${tags[a-1]}"; break; fi
      for t in "${tags[@]}"; do [[ "$t" == "$a" ]] && { choice="$a"; break 2; }; done
      if [[ "${tags[0]}" == "yes" ]]; then
        case "${a,,}" in y|yes) choice=yes; break ;; n|no) choice=no; break ;; esac
      fi
      say "Please type a number from the list."
    done
    bar_line
  fi
  printf '%s' "$choice"
}

# ui_multi "question" tag1 label1 tag2 label2 ...  -> echo ticked tags (space separated)
ui_multi() {
  local text="$1"; shift
  local tags=() labels=() ticked=() n=0 sel=0 i li tl=() picked=()
  while (( $# >= 2 )); do tags+=("$1"); labels+=("$(L "$2")"); ticked+=(0); n=$((n+1)); shift 2; done
  mapfile -t tl < <(_wrap "$text")
  if (( FANCY )); then
    local vis=$(( ROWS - ${#tl[@]} - 5 )) top=0 drawn=0 key k2 more=0 box
    (( vis > 14 )) && vis=14; (( vis < 3 )) && vis=3; (( vis > n )) && vis=n
    (( vis < n )) && more=1
    cursor_hide
    while true; do
      (( sel < top )) && top=$sel
      (( sel >= top + vis )) && top=$(( sel - vis + 1 ))
      (( drawn )) && printf '\e[%dA\r\e[J' "$drawn" >&2
      printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_ACT" "$C_RESET" "$C_BOLD" "${tl[0]}" "$C_RESET" >&2
      for (( li=1; li<${#tl[@]}; li++ )); do printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$C_DIM" "${tl[li]}" "$C_RESET" >&2; done
      for (( i=top; i<top+vis; i++ )); do
        if (( ticked[i] )); then box="${C_GREEN}${S_BOXON}${C_RESET}"; else box="${C_DIM}${S_BOXOFF}${C_RESET}"; fi
        if (( i == sel )); then printf '%s%s%s  %s %s%s%s%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$box" "$C_BOLD$C_ACC" "${labels[i]}" "$C_RESET" "" >&2
        else printf '%s%s%s  %s %s%s%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$box" "$C_DIM" "${labels[i]}" "$C_RESET" >&2; fi
      done
      (( more )) && printf '%s%s%s  %s%d/%d  (up/down for more)%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$C_DIM" $(( sel + 1 )) "$n" "$C_RESET" >&2
      printf '%s%s%s\n' "$C_ACC" "$S_END" "$C_RESET" >&2
      drawn=$(( ${#tl[@]} + vis + more + 1 ))
      IFS= read -rsn1 key || { cursor_show; cancelled; }
      if [[ "$key" == $'\e' ]]; then IFS= read -rsn2 -t 0.2 k2 || true; key+="$k2"; fi
      case "$key" in
        $'\e[A'|$'\eOA'|k) (( sel > 0 )) && sel=$(( sel - 1 )) || sel=$(( n - 1 )) ;;
        $'\e[B'|$'\eOB'|j) (( sel < n - 1 )) && sel=$(( sel + 1 )) || sel=0 ;;
        ' ') ticked[sel]=$(( 1 - ticked[sel] )) ;;
        a|A) local all=1; for (( i=0; i<n; i++ )); do (( ticked[i] )) || all=0; done
             for (( i=0; i<n; i++ )); do ticked[i]=$(( 1 - all )); done ;;
        '') break ;;
      esac
    done
    printf '\e[%dA\r\e[J' "$drawn" >&2
    cursor_show
  else
    local a x
    printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_ACT" "$C_RESET" "$C_BOLD" "${tl[0]}" "$C_RESET" >&2
    for (( i=0; i<n; i++ )); do printf '%s%s%s  %2d) %s\n' "$C_GRAY" "$S_BAR" "$C_RESET" $(( i + 1 )) "${labels[i]}" >&2; done
    printf '%s%s%s  Numbers separated by spaces (e.g. 1 4 7), or Enter for none: ' "$C_GRAY" "$S_BAR" "$C_RESET" >&2
    IFS= read -r a || cancelled
    for x in $a; do [[ "$x" =~ ^[0-9]+$ ]] && (( x >= 1 && x <= n )) && ticked[x-1]=1; done
  fi
  for (( i=0; i<n; i++ )); do (( ticked[i] )) && picked+=("${tags[i]}"); done
  _done_block "${tl[0]%% (*}" "${picked[*]:-(none)}"
  printf '%s' "${picked[*]:-}"
}

# ui_yesno "question" [default yes|no]  -> exit status 0 for yes
ui_yesno() {
  local c
  c=$(ui_menu "$1" "${2:-yes}" "yes" "Yes" "no" "No")
  [[ "$c" == "yes" ]]
}

# ui_input "question" "default" [password]  -> echo value
ui_input() {
  local text="$1" def="$2" out="" tl=() li
  mapfile -t tl < <(_wrap "$text")
  if (( FANCY )); then
    local drawn=$(( ${#tl[@]} + 2 )) rd=(-r -e)
    printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_ACT" "$C_RESET" "$C_BOLD" "${tl[0]}" "$C_RESET" >&2
    for (( li=1; li<${#tl[@]}; li++ )); do printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_BAR" "$C_RESET" "$C_DIM" "${tl[li]}" "$C_RESET" >&2; done
    printf '%s%s%s\n' "$C_ACC" "$S_END" "$C_RESET" >&2
    printf '\e[1A\r' >&2
    if [[ "${3:-}" == "password" ]]; then rd=(-r -s); else rd+=(-i "$def"); fi
    IFS= read "${rd[@]}" -p "${S_BAR}  " out || cancelled
    printf '\r\e[%dA\e[J' $(( drawn - 1 )) >&2
    if [[ "${3:-}" == "password" ]]; then _done_block "${tl[0]}" "(hidden)"; else _done_block "${tl[0]}" "${out:-$def}"; fi
    [[ -z "$out" ]] && out="$def"
  else
    printf '%s%s%s  %s%s%s\n' "$C_ACC" "$S_ACT" "$C_RESET" "$C_BOLD" "${tl[0]}" "$C_RESET" >&2
    for (( li=1; li<${#tl[@]}; li++ )); do say "${C_DIM}${tl[li]}${C_RESET}"; done
    printf '%s%s%s  [%s]: ' "$C_GRAY" "$S_BAR" "$C_RESET" "$([[ ${3:-} == password ]] && echo hidden || echo "$def")" >&2
    if [[ "${3:-}" == "password" ]]; then IFS= read -r -s out || cancelled; echo >&2; else IFS= read -r out || cancelled; fi
    [[ -z "$out" ]] && out="$def"
    bar_line
  fi
  printf '%s' "$out"
}

# ----------------------------------------------------------------------------
#  Version lookups (official APIs)
# ----------------------------------------------------------------------------
MANIFEST_JSON=""
mojang_manifest() { [[ -z "$MANIFEST_JSON" ]] && MANIFEST_JSON=$(fetch "$MOJANG_MANIFEST"); printf '%s' "$MANIFEST_JSON"; }

vanilla_versions() {   # newest first, releases only
  mojang_manifest | jq -r '.versions[] | select(.type=="release") | .id'
}
paper_versions() {     # newest first, stable releases only (no -rc / -pre)
  fetch "$PAPER_API/paper" | jq -r '.versions | to_entries[] | .value[]' | grep -Ev -- '-(rc|pre)' || true
}
velocity_latest() {
  fetch "$PAPER_API/velocity" | jq -r '[.versions | to_entries[] | .value[] | select(test("SNAPSHOT")|not)] | first'
}
mojang_version_json() {  # <id>
  local url
  url=$(mojang_manifest | jq -r --arg v "$1" '.versions[] | select(.id==$v) | .url')
  [[ -n "$url" && "$url" != "null" ]] || return 1
  fetch "$url"
}
java_for_mc() {   # <mc version> -> required Java major
  local j=""
  j=$(mojang_version_json "$1" 2>/dev/null | jq -r '.javaVersion.majorVersion // empty' 2>/dev/null || true)
  if [[ -n "$j" ]]; then echo "$j"; return; fi
  # Fallback rules if Mojang does not know the version
  if   ver_ge "$1" "26.0";   then echo 25
  elif ver_ge "$1" "1.20.5"; then echo 21
  elif ver_ge "$1" "1.18";   then echo 17
  elif ver_ge "$1" "1.17";   then echo 16
  else echo 8; fi
}

pick_version() {  # <label> <versions newest first...>  -> echo version
  local label="$1" v items=() i=0 choice; shift
  local all=("$@")
  (( ${#all[@]} > 0 )) || die "Could not get the $label version list (network problem?)."
  for v in "${all[@]}"; do
    items+=("$v" "$([[ $i -eq 0 ]] && L 'Newest (recommended)' || echo '')")
    i=$((i+1)); (( i >= 15 )) && break
  done
  items+=("other" "Type a specific older version")
  choice=$(ui_menu "Which Minecraft version? (newest first)" "${all[0]}" "${items[@]}")
  while [[ "$choice" == "other" ]]; do
    choice=$(ui_input "Type the exact Minecraft version (e.g. 1.20.1):" "${all[0]}")
    if ! printf '%s\n' "${all[@]}" | grep -qxF -- "$choice"; then ui_msg "That version is not available. Pick one from the list instead."; choice=$(ui_menu "Which Minecraft version? (newest first)" "${all[0]}" "${items[@]}"); fi
  done
  printf '%s' "$choice"
}

# ----------------------------------------------------------------------------
#  Java
# ----------------------------------------------------------------------------
java_major() {   # <java binary> -> major version number
  local v
  v=$("$1" -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')
  [[ -z "$v" ]] && { echo 0; return; }
  if [[ "$v" == 1.* ]]; then echo "$v" | cut -d. -f2; else echo "${v%%[.+-]*}"; fi
}

ensure_java() {  # <required major> -> echo path to java binary
  local req="$1" sys local_dir
  if command -v java >/dev/null 2>&1 && { (( ! IS_MAC )) || /usr/libexec/java_home >/dev/null 2>&1; }; then   # on a Mac /usr/bin/java is only a stub when no Java is installed
    sys=$(java_major java)
    if (( sys >= req )); then info "Using system Java $sys (needs $req+)." >&2; command -v java; return; fi
    warn "System Java is $sys but this server needs Java $req+." >&2
  fi
  local feat="$req"; (( feat == 16 )) && feat=17
  local_dir="$INSTALL_DIR/java/jre-$feat"
  if [[ -x "$local_dir/bin/java" ]]; then echo "$local_dir/bin/java"; return; fi
  [[ -n "$ARCH_JDK" ]] || die "No Java $req+ found and your CPU ($ARCH_RAW) is not supported for auto-download. Install Java $req manually."
  info "Downloading Eclipse Temurin Java $feat (into $INSTALL_DIR/java, no root needed) ..." >&2
  mkdir -p "$local_dir"
  local tgz="$INSTALL_DIR/java/temurin-$feat.tar.gz"
  local kind
  for kind in jre jdk; do
    if curl -fL --retry 3 -A "$UA" --progress-bar -o "$tgz" \
        "$ADOPTIUM_API/$feat/ga/$OS_JDK/$ARCH_JDK/$kind/hotspot/normal/eclipse" >&2; then break; fi
    rm -f "$tgz"
  done
  [[ -f "$tgz" ]] || die "Could not download Java $feat. Install it with your package manager and re-run."
  tar -xzf "$tgz" -C "$local_dir" --strip-components=1
  rm -f "$tgz"
  if [[ -x "$local_dir/Contents/Home/bin/java" ]]; then   # macOS builds are packed as an app bundle
    cp -R "$local_dir/Contents/Home/." "$local_dir/" && rm -rf "$local_dir/Contents"
  fi
  [[ -x "$local_dir/bin/java" ]] || die "Java download looks broken."
  ok "Java $feat installed at $local_dir" >&2
  echo "$local_dir/bin/java"
}

# ----------------------------------------------------------------------------
#  Downloads of server software
# ----------------------------------------------------------------------------
download_vanilla() {  # <version> <dest>
  local vj url sha
  vj=$(mojang_version_json "$1") || die "Mojang does not know version $1."
  url=$(jq -r '.downloads.server.url // empty' <<<"$vj")
  sha=$(jq -r '.downloads.server.sha1 // empty' <<<"$vj")
  [[ -n "$url" ]] || die "Mojang has no server download for $1."
  download "$url" "$2"
  verify_hash "$2" sha1 "$sha"
}
download_papermc() {  # <project> <version> <dest>
  local bj url sha build channel
  bj=$(fetch "$PAPER_API/$1/versions/$2/builds/latest") || die "PaperMC has no $1 build for $2."
  url=$(jq -r '.downloads["server:default"].url // empty' <<<"$bj")
  sha=$(jq -r '.downloads["server:default"].checksums.sha256 // empty' <<<"$bj")
  build=$(jq -r '.id' <<<"$bj"); channel=$(jq -r '.channel // "?"' <<<"$bj")
  [[ -n "$url" ]] || die "No download URL in PaperMC response for $1 $2."
  [[ "$channel" != "STABLE" ]] && warn "$1 $2 build $build is marked $channel (not STABLE)."
  info "$1 $2 build #$build"
  download "$url" "$3"
  verify_hash "$3" sha256 "$sha"
}

# ----------------------------------------------------------------------------
#  Config writers
# ----------------------------------------------------------------------------
motd_props() { printf '%s' "$1" | sed -E 's/&([0-9a-fk-orA-FK-OR])/\\u00A7\1/g'; }   # &6 -> section-sign escape

write_server_properties() {  # <dir> <bind ip> <port> <online true/false>
  local f="$1/server.properties" kv k
  cat >"$f" <<EOF
# Generated by mc-setup.sh on $(date)
motd=$(motd_props "$MOTD")
server-ip=${2}
server-port=${3}
online-mode=${4}
max-players=${MAX_PLAYERS}
gamemode=${GAMEMODE}
force-gamemode=${FORCE_GM}
difficulty=${DIFFICULTY}
hardcore=${HARDCORE}
pvp=${PVP}
white-list=${WHITELIST}
enforce-whitelist=${WHITELIST}
view-distance=${VIEW_DIST}
simulation-distance=${SIM_DIST}
spawn-protection=${SPAWN_PROT}
enable-command-block=${CMD_BLOCKS}
allow-flight=${ALLOW_FLIGHT}
allow-nether=${ALLOW_NETHER}
generate-structures=${GEN_STRUCT}
spawn-animals=${SPAWN_ANIMALS}
spawn-monsters=${SPAWN_MONSTERS}
spawn-npcs=${SPAWN_NPCS}
player-idle-timeout=${IDLE_TIMEOUT}
level-name=${LEVEL_NAME}
level-seed=${SEED}
level-type=minecraft\:${LEVEL_TYPE}
resource-pack=${RES_PACK_URL}
resource-pack-sha1=${RES_PACK_SHA1}
require-resource-pack=${RES_PACK_REQ}
enforce-secure-profile=${4}
EOF
  if (( ${#EXTRA_PROPS[@]} )); then
    for kv in "${EXTRA_PROPS[@]}"; do
      k="${kv%%=*}"
      sedi "/^${k//./\\.}=/d" "$f"
      printf '%s\n' "$kv" >>"$f"
    done
  fi
  echo "eula=true" >"$1/eula.txt"
}

AIKAR_FLAGS="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1"

write_start_script() {  # <dir> <java> <xmx MB> <xms MB> <extra flags> <launch args, e.g. "-jar server.jar --nogui">
  if [[ -n "$5" ]] && ! "$2" $5 -version >/dev/null 2>&1; then   # a flag this Java doesn't know makes it refuse to start
    warn "This Java does not accept some of the tuning flags - using a simple, safe set instead."
    set -- "$1" "$2" "$3" "$4" "-XX:+UseG1GC" "$6"
  fi
  local run="\"\$JAVA\" -Xms${4}M -Xmx${3}M $5 $6"
  {
    echo '#!/usr/bin/env bash'
    echo '# Starts this server. Generated by mc-setup.sh'
    echo 'cd "$(dirname "$0")"'
    echo "JAVA=\"$2\""
    if [[ "$AUTORESTART" == "true" ]]; then
      echo 'while true; do'
      echo "  $run"
      echo '  code=$?'
      echo '  [[ $code -eq 0 ]] && break      # clean stop (stop/end command) = do not restart'
      echo '  echo "[stopped with an error (code $code). Scroll up to see why. Restarting in 10 seconds - press Ctrl+C to cancel]"'
      echo '  sleep 10'
      echo 'done'
    else
      echo "$run"
      echo 'code=$?'
      echo 'if [[ $code -ne 0 ]]; then'
      echo '  echo; echo "[Server stopped with an error (code $code)]"'
      echo '  echo "  - Could not create the Java Virtual Machine: Java or memory settings are wrong (lower the RAM, or re-run mc-setup)."'
      echo '  echo "  - Address already in use: another server is already running on this port."'
      echo '  echo "  - Unsupported class file / requires Java: wrong Java version for this Minecraft."'
      echo '  echo "The exact message is just above; logs/latest.log has more."'
      echo '  read -rp "Press Enter to close " _ || true'
      echo 'fi'
      echo 'exit $code'
    fi
  } >"$1/start.sh"
  chmod +x "$1/start.sh"
}

configure_velocity_toml() {  # <proxy dir> <java>
  local d="$1" f="$1/velocity.toml"
  local MOTD_SED="${MOTD//\\/\\\\}"; MOTD_SED="${MOTD_SED//|/\\|}"; MOTD_SED="${MOTD_SED//&/\\&}"
  info "Generating default Velocity config (first launch, takes a few seconds) ..."
  ( cd "$d" && exec "$2" -Xmx256M -jar velocity.jar </dev/null >"$d/first-run.log" 2>&1 ) &
  local pid=$! i
  for i in $(seq 1 90); do
    grep -q 'Done' "$d/first-run.log" 2>/dev/null && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  kill "$pid" 2>/dev/null || true   # SIGTERM -> Velocity shuts down cleanly
  wait "$pid" 2>/dev/null || true

  if [[ ! -f "$f" ]]; then
    warn "Velocity did not create a config; writing a minimal one."
    cat >"$f" <<EOF
config-version = "2.7"
bind = "0.0.0.0:${PORT}"
motd = "${MOTD}"
show-max-players = ${MAX_PLAYERS}
online-mode = ${ONLINE}
force-key-authentication = ${ONLINE}
player-info-forwarding-mode = "modern"
forwarding-secret-file = "forwarding.secret"

[servers]
lobby = "127.0.0.1:${BACKEND_PORT}"
try = ["lobby"]

[forced-hosts]
EOF
  else
    # Edit the generated defaults in place
    sedi -E \
      -e "s|^bind *=.*|bind = \"0.0.0.0:${PORT}\"|" \
      -e "s|^online-mode *=.*|online-mode = ${ONLINE}|" \
      -e "s|^force-key-authentication *=.*|force-key-authentication = ${ONLINE}|" \
      -e "s|^player-info-forwarding-mode *=.*|player-info-forwarding-mode = \"modern\"|" \
      -e "s|^show-max-players *=.*|show-max-players = ${MAX_PLAYERS}|" \
      -e "s|^motd *=.*|motd = \"${MOTD_SED}\"|" "$f"
    # Replace example servers with our single backend, clear example forced hosts
    awk -v be="127.0.0.1:${BACKEND_PORT}" '
      /^\[/ { sec=$0 }
      sec=="[servers]" && /^\[servers\]/ { print; print "lobby = \"" be "\""; next }
      sec=="[servers]" && /^[[:space:]]*try[[:space:]]*=/ { print "try = [\"lobby\"]"; skip=($0 !~ /\]/); next }
      sec=="[servers]" && skip { if ($0 ~ /\]/) skip=0; next }
      sec=="[servers]" && /^[[:space:]]*[A-Za-z0-9_."-]+[[:space:]]*=/ { next }
      sec=="[forced-hosts]" && /^\[forced-hosts\]/ { print; next }
      sec=="[forced-hosts]" && /=/ { fskip=($0 !~ /\]/); next }
      sec=="[forced-hosts]" && fskip { if ($0 ~ /\]/) fskip=0; next }
      { print }' "$f" >"$f.new" && mv "$f.new" "$f"
  fi
  [[ -f "$d/forwarding.secret" ]] || head -c 24 /dev/urandom | base64 | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 16 >"$d/forwarding.secret"
  rm -rf "$d/logs" "$d/first-run.log"
  ok "Velocity configured (modern forwarding -> 127.0.0.1:${BACKEND_PORT})"
}

configure_paper_for_velocity() {  # <backend dir> <secret>
  local d="$1" secret="$2"
  if ver_ge "$MC_VERSION" "1.19"; then
    mkdir -p "$d/config"
    cat >"$d/config/paper-global.yml" <<EOF
# Partial config written by mc-setup.sh - Paper fills in the rest on first start
proxies:
  velocity:
    enabled: true
    online-mode: ${ONLINE}
    secret: '${secret}'
EOF
  else
    cat >"$d/paper.yml" <<EOF
# Partial config written by mc-setup.sh - Paper fills in the rest on first start
settings:
  velocity-support:
    enabled: true
    online-mode: ${ONLINE}
    secret: '${secret}'
EOF
  fi
  ok "Paper backend set to accept Velocity modern forwarding"
}

# ----------------------------------------------------------------------------
#  Networking helpers
# ----------------------------------------------------------------------------
lan_ip() {
  if (( IS_MAC )); then
    local ifc; ifc=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
    ipconfig getifaddr "${ifc:-en0}" 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
  else
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || hostname -I 2>/dev/null | awk '{print $1}'
  fi
}
public_ip() { curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 6 https://ifconfig.me 2>/dev/null || echo "unknown"; }

open_firewall() {  # <port> [tcp|udp]
  local proto="${2:-tcp}"
  if (( IS_MAC )); then
    info "On a Mac nothing needs opening here. The first time Java starts, macOS asks 'Do you want the application java to accept incoming network connections?' - click Allow."
  elif [[ $EUID -ne 0 && -z "$SUDO" ]]; then
    info "Opening a firewall port needs administrator rights, and this account has none. If a firewall is active, ask an administrator to allow ${proto^^} port $1."
  elif command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
    $SUDO ufw allow "$1/$proto" comment "Minecraft" && ok "ufw: opened ${proto^^} $1"
  elif command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state >/dev/null 2>&1; then
    $SUDO firewall-cmd --permanent --add-port="$1/$proto" && $SUDO firewall-cmd --reload && ok "firewalld: opened ${proto^^} $1"
  else
    info "No active ufw/firewalld found - nothing to open on this machine."
  fi
}

try_upnp() {  # <port> [TCP|UDP]
  local proto="${2:-TCP}"
  command -v upnpc >/dev/null 2>&1 || pkg_install miniupnpc || { warn "Could not install miniupnpc (upnpc)."; return 1; }
  local ip; ip=$(lan_ip)
  if upnpc -e "Minecraft" -a "$ip" "$1" "$1" "$proto" >/tmp/mcs-upnp.log 2>&1 && grep -qi "is redirected" /tmp/mcs-upnp.log; then
    ok "UPnP: router now forwards $proto $1 -> $ip:$1"
    if [[ ! -f "$INSTALL_DIR/upnp-refresh.sh" ]]; then
      cat >"$INSTALL_DIR/upnp-refresh.sh" <<EOF
#!/usr/bin/env bash
# Re-adds the UPnP port mappings (some routers forget them after a reboot)
if [ "\$(uname -s)" = "Darwin" ]; then
  IFC=\$(route -n get default 2>/dev/null | awk '/interface:/{print \$2; exit}'); IP=\$(ipconfig getifaddr "\${IFC:-en0}")
else
  IP=\$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if(\$i=="src"){print \$(i+1); exit}}')
fi
EOF
      chmod +x "$INSTALL_DIR/upnp-refresh.sh"
    fi
    printf 'upnpc -e "Minecraft" -a "$IP" %s %s %s\n' "$1" "$1" "$proto" >>"$INSTALL_DIR/upnp-refresh.sh"
    return 0
  fi
  warn "UPnP did not work (router may have it disabled). See the manual steps."
  return 1
}

# ----------------------------------------------------------------------------
#  playit.gg tunnel guide: one small step per screen
# ----------------------------------------------------------------------------
PUBLIC_ADDR=""
open_url() {   # open a web page in the default browser if we can
  if (( IS_MAC )) && command -v open >/dev/null 2>&1; then open "$1" >/dev/null 2>&1 &
  elif command -v xdg-open >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then xdg-open "$1" >/dev/null 2>&1 &
  else ui_msg "Open this link in your browser:  $1"; fi
  return 0
}
tunnel_guide() {
  local TG_T=() TG_U=() TG_B=() i=0 n c a
  TG_T[0]="What we are going to do"; TG_U[0]=""
  TG_B[0]="A tunnel lets friends reach your server over the internet without touching your router. playit.gg is free and needs no credit card.

You will do 7 small things:
 1. Make a free playit.gg account
 2. Install the playit program on this PC
 3. Connect (claim) this PC to your account
 4. Create a Minecraft tunnel
 5. Copy the address playit gives you
 6. Paste it here so it is saved
 7. Test it

It takes about 10 minutes. Each screen is one small step. Do it, then press Enter on 'Done'. You can go Back any time."
  TG_T[1]="Make your free playit.gg account"; TG_U[1]="https://playit.gg/"
  TG_B[1]="1. Open https://playit.gg  (choose 'Open the page for me' below if you like).
2. Click the 'Login' button at the top right.
3. Click 'Create an account' and sign up with Google, Discord or an email and password.
4. If it asks you to verify your email, open your email, click the link, then come back to the site.
>> You should now see your playit.gg dashboard (a page with a menu on the left).

If you already have an account: just log in and go to the next step.
If you did not get the email: check Spam, or wait 2 minutes and click 'resend'."
  TG_T[2]="Download and install playit"; TG_U[2]="https://playit.gg/download"
  if (( IS_MAC )); then TG_U[2]="https://playit.gg/download/macos"; fi
  TG_B[2]="1. Open a terminal. On Ubuntu or Debian type these three lines, one at a time:
>> curl -SsL https://playit-cloud.github.io/ppa/key.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/playit.gpg >/dev/null
>> echo \"deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./\" | sudo tee /etc/apt/sources.list.d/playit-cloud.list
>> sudo apt update && sudo apt install playit
2. On other systems open https://playit.gg/download and pick your system (.rpm, .apk or a plain binary).

If apt says 'unable to locate package playit': you missed one of the first two lines. Repeat them."
  if (( IS_MAC )); then
    TG_B[2]="1. Open https://playit.gg/download/macos  (choose 'Open the page for me' below).
2. Download the Mac installer. It is a file ending in .pkg and works on both Apple Silicon and Intel Macs.
   (If the page only offers 'build from source', go to https://github.com/playit-cloud/playit-agent/releases and download the file named playit-<version>.pkg.)
3. Open the downloaded .pkg and click Continue / Install. Type your Mac password when asked.
>> If macOS says it 'cannot be opened because it is from an unidentified developer': right-click the file, choose Open, then Open again.
>> You should see an 'Installation was successful' screen.

No .pkg? Download playit-macos-universal.tar.gz instead, double-click it to unpack, then in Terminal go to that folder and type  ./playit
If you use Homebrew and it has a 'playit' formula you can also try:  brew install playit"
  fi
  TG_T[3]="Open playit and get the claim link"; TG_U[3]=""
  TG_B[3]="1. In a terminal type:
>> playit
2. Leave that terminal open.
>> You should see a message that this computer is not linked yet, with a link like  https://playit.gg/claim/xxxxxx

The package also installs a background service. To keep playit running after you close the terminal use:
>> sudo systemctl enable --now playit
If systemctl says 'unit not found': keep the terminal open (or run it inside tmux) instead."
  if (( IS_MAC )); then
    TG_B[3]="1. After the installer finishes, the playit window opens by itself (or open Terminal and type  playit ).
2. Leave it open.
>> You should see a message that this Mac is not linked yet, with a link like  https://playit.gg/claim/xxxxxx

The installer also adds a background service (it starts when you log in and keeps your tunnel online), so you normally do not need to keep a window open afterwards.
If macOS asks whether playit may run in the background or find devices on your local network: click Allow.
Logs, if something goes wrong:  ~/Library/Logs/playit"
  fi
  TG_T[4]="Claim this computer"; TG_U[4]=""
  TG_B[4]="1. Click the claim link in the playit window, or copy it into your web browser.
2. Make sure you are logged in to playit.gg (step 2).
3. Click the button 'Add Agent' (it may say 'Approve' or 'Claim').
4. Go back to the playit window.
>> You should see it change to 'Connected' or 'Online' (a green status).

If the page says 'invalid' or 'expired': go back to the playit window, get a fresh link and try again.
If it never turns green after 1 minute: check your internet, then close and reopen playit."
  TG_T[5]="Create your Minecraft tunnel"; TG_U[5]="https://playit.gg/account/setup/new-tunnel"
  TG_B[5]="1. Open https://playit.gg/account/setup/new-tunnel  (or on the dashboard click 'Create tunnel').
2. Tunnel type:  choose  Minecraft Java.
3. Region:  pick the one closest to you and your friends. 'Global' is free and fine.
4. Agent:  pick the computer you just added (it has a green dot).
5. Local address (type exactly this):
>> 127.0.0.1
6. Local port (your server port):
>> ${PORT}
7. Click 'Create tunnel' (or 'Add tunnel').
>> You should now see your new tunnel in a list, marked as active.

If the port box is not shown: open the tunnel after creating it and click its Edit or 'Origin' settings.
If it says 'free limit reached': delete an old tunnel on the same page first."
  TG_T[6]="Copy your public address"; TG_U[6]="https://playit.gg/account/tunnels"
  TG_B[6]="1. Open https://playit.gg/account/tunnels  (left menu: 'Tunnels') and click your Minecraft tunnel.
2. Find the field called 'Address' or 'Allocation' (also called Shared IP).
>> It looks like  something.joinmc.link  or  12.ip.gl.ply.gg:34567
3. Click it to copy. Keep the number after the colon if there is one!

If you see two addresses: use the one for 'Minecraft Java'.
If the address says 'pending' or 'allocating': wait a minute and refresh the page."
  TG_T[7]="Paste the address here"; TG_U[7]=""
  TG_B[7]="NEXT SCREEN asks for the address you copied. Paste it with right-click (or Ctrl+V; in Windows Terminal also Ctrl+Shift+V).
It is saved, shown in your final summary, and remembered for later.

If you do not have it yet: go Back one step."
  TG_T[8]="Test it"; TG_U[8]=""
  TG_B[8]="1. Start your server:
>> ${INSTALL_DIR}/start-all.sh --attach
   Wait until it says  Done  (about a minute the first time).
2. Open Minecraft Java Edition, click Multiplayer, then 'Add Server'.
3. Paste your playit address in 'Server Address', click Done, then double-click the server.
>> You should see your server name and join.

Friends do exactly the same with the same address. They install nothing.

If it says 'Can't connect to server':
 - Is the server finished starting, and is playit running?
 - Is the tunnel active on playit.gg and the tunnel port ${PORT} the same as your server port?
 - Did you copy the number after the colon?
 - Same Minecraft version as the server?
Still stuck? Run mc-setup again and choose an ngrok tunnel or router port forwarding instead."
  local paste_i=7
  if [[ "$BEDROCK" == true ]]; then
    TG_B[8]="${TG_B[8]/They install nothing./They install nothing.
Bedrock players: open Minecraft Bedrock, Play > Servers > Add Server. Type the Bedrock address in 'Server Address' and its port number in 'Port' (two separate boxes). Join as usual.}"
    TG_T=("${TG_T[@]:0:7}" "Add a second tunnel for Bedrock players" "${TG_T[@]:7}")
    TG_U=("${TG_U[@]:0:7}" "https://playit.gg/account/setup/new-tunnel" "${TG_U[@]:7}")
    TG_B=("${TG_B[@]:0:7}" "Bedrock players (phones, consoles, Windows 10/11) use UDP, so they need their own tunnel.
1. Open https://playit.gg/account/setup/new-tunnel  (or click 'Create tunnel' again).
2. Tunnel type:  choose  Minecraft Bedrock.
3. Region and Agent:  the same as for the Java tunnel.
4. Local address (type exactly this):
>> 127.0.0.1
5. Local port (Geyser's port):
>> ${BEDROCK_PORT}
6. Click 'Create tunnel'.
7. On https://playit.gg/account/tunnels open the Bedrock tunnel and copy its address and port.
>> It looks like  something.joinmc.link  and a port number such as  34567.

If it says 'free limit reached': delete an old tunnel on the same page first." "${TG_B[@]:7}")
    paste_i=8
  fi
  n=${#TG_T[@]}
  while (( i < n )); do
    ui_box "Step $((i+1)) of $n - ${TG_T[i]}" "${TG_B[i]}"
    if (( i == paste_i )); then   # the paste step
      a=$(ui_input "Paste your playit address here (or press Enter to do it later)" "$PUBLIC_ADDR")
      a="${a//[[:space:]]/}"; a="${a#minecraft://}"
      if [[ -n "$a" ]]; then PUBLIC_ADDR="$a"; ok "Saved: $PUBLIC_ADDR"; fi
      if [[ "$BEDROCK" == true ]]; then
        a=$(ui_input "Paste your Bedrock address here, with its port (for example  something.joinmc.link:34567)" "$PUBLIC_ADDR_BE")
        a="${a//[[:space:]]/}"
        if [[ -n "$a" ]]; then PUBLIC_ADDR_BE="$a"; ok "Saved: $PUBLIC_ADDR_BE"; fi
      fi
      i=$((i+1)); continue
    fi
    local opts=("next" "Done - go to the next step")
    [[ -n "${TG_U[i]}" ]] && opts+=("open" "Open the page for me")
    (( i > 0 )) && opts+=("back" "Go back one step")
    opts+=("quit" "Skip the rest (I will do it later)")
    c=$(ui_menu "What now?" "next" "${opts[@]}")
    case "$c" in
      next) i=$((i+1)) ;;
      open) open_url "${TG_U[i]}" ;;
      back) i=$((i-1)) ;;
      quit) break ;;
    esac
  done
  if [[ -n "$PUBLIC_ADDR" ]]; then
    ui_msg "Your public address: $PUBLIC_ADDR   (friends use this to join)"
    [[ -n "$PUBLIC_ADDR_BE" ]] && ui_msg "Your Bedrock address: $PUBLIC_ADDR_BE   (Bedrock players use this)"
  else ui_msg "No problem. Run   bash mc-setup.sh --tunnel-guide   any time to continue."; fi
  return 0
}

install_geyser() {   # <server dir>  Geyser + Floodgate for Bedrock players (Paper)
  local d="$1/plugins" gd="$1/plugins/Geyser-Spigot" base="https://download.geysermc.org/v2/projects"
  mkdir -p "$d" "$gd"
  info "Downloading Geyser and Floodgate (Bedrock support) ..."
  download "$base/geyser/versions/latest/builds/latest/downloads/spigot" "$d/Geyser-Spigot.jar"
  download "$base/floodgate/versions/latest/builds/latest/downloads/spigot" "$d/floodgate-spigot.jar"
  # Bedrock port, and let Floodgate log Bedrock players in (no Java account needed)
  cat >"$gd/config.yml" <<EOF
bedrock:
  port: $BEDROCK_PORT
  clone-remote-port: false
java:
  auth-type: floodgate
EOF
  ok "$(Lf "Bedrock support installed (Geyser + Floodgate, UDP {0})" "$BEDROCK_PORT")"
}

install_playit() {
  # playit 2.x runs as a background service with its own window, so there is nothing to download here:
  # the guide below walks through installing it.
  ok "playit.gg selected - a step-by-step guide follows"
}

install_ngrok() {
  [[ -n "$ARCH_NGROK" ]] || die "ngrok has no build for $ARCH_RAW."
  mkdir -p "$INSTALL_DIR/tools"
  local tgz="$INSTALL_DIR/tools/ngrok.tgz"
  download "$NGROK_BASE/ngrok-v3-stable-$OS_NGROK-$ARCH_NGROK.tgz" "$tgz"
  tar -xzf "$tgz" -C "$INSTALL_DIR/tools" && rm -f "$tgz"
  chmod +x "$INSTALL_DIR/tools/ngrok"
  if [[ -n "$NGROK_TOKEN" ]]; then
    "$INSTALL_DIR/tools/ngrok" config add-authtoken "$NGROK_TOKEN" --config "$INSTALL_DIR/tools/ngrok.yml" >/dev/null \
      && ok "ngrok authtoken saved"
  fi
  cat >"$INSTALL_DIR/start-tunnel.sh" <<EOF
#!/usr/bin/env bash
# ngrok TCP tunnel. Friends connect to the tcp://X.tcp.ngrok.io:NNNNN address
# it shows (without "tcp://"). The address changes every restart on free plans.
cd "\$(dirname "\$0")"
exec ./tools/ngrok tcp ${PORT} --config ./tools/ngrok.yml
EOF
  chmod +x "$INSTALL_DIR/start-tunnel.sh"
  ok "ngrok installed"
}

# ----------------------------------------------------------------------------
#  Launcher + systemd
# ----------------------------------------------------------------------------
server_session() {   # tmux/screen session name from the server name
  local n; n=$(printf '%s' "$SERVER_NAME" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed -E 's/^-+//; s/-+$//')
  echo "${n:-minecraft}"
}
write_launchers() {
  local SESSION; SESSION=$(server_session)
  local parts=()
  [[ "$TUNNEL" == "ngrok" ]] && parts+=("tunnel:./start-tunnel.sh")
  if [[ "$SETUP" == "velocity" ]]; then
    parts+=("backend:./backend/start.sh" "proxy:./proxy/start.sh")
  else
    parts+=("server:./server/start.sh")
  fi
  {
    echo '#!/usr/bin/env bash'
    echo "# $SERVER_NAME - starts everything inside a tmux (or screen) session called \"$SESSION\"."
    echo "# Reattach later with:  tmux attach -t $SESSION   (detach: Ctrl+B then D)"
    echo 'cd "$(dirname "$0")"'
    echo "S=$SESSION"
    echo 'if command -v tmux >/dev/null 2>&1; then'
    echo '  if tmux has-session -t $S 2>/dev/null; then echo "Already running. Attach with: tmux attach -t $S"; exit 0; fi'
    local first=1 p name cmd
    for p in "${parts[@]}"; do
      name="${p%%:*}"; cmd="${p#*:}"
      if (( first )); then echo "  tmux new-session -d -s \$S -c \"\$PWD\" -n $name '$cmd; read -p \"[$name stopped] press Enter\"'"; first=0
      else echo "  sleep 3; tmux new-window -t \$S -c \"\$PWD\" -n $name '$cmd; read -p \"[$name stopped] press Enter\"'"; fi
    done
    echo "  echo \"Started. Attach with: tmux attach -t $SESSION  (switch windows: Ctrl+B then N)\""
    echo '  [[ "${1:-}" == "--attach" ]] && exec tmux attach -t $S'
    echo 'elif command -v screen >/dev/null 2>&1; then'
    for p in "${parts[@]}"; do
      name="${p%%:*}"; cmd="${p#*:}"
      echo "  screen -dmS mc-$name bash -c '$cmd'; sleep 3"
    done
    echo '  echo "Started in screen sessions. List: screen -ls   Attach: screen -r mc-<name>  (detach: Ctrl+A then D)"'
    echo "  [[ \"\${1:-}\" == \"--attach\" ]] && exec screen -r mc-${parts[-1]%%:*}"
    echo 'else'
    echo '  echo "tmux/screen not found - starting in background, logs in ./logs/"'
    echo '  mkdir -p logs'
    for p in "${parts[@]}"; do
      name="${p%%:*}"; cmd="${p#*:}"
      if [[ "$name" == "${parts[-1]%%:*}" ]]; then
        echo "  echo \"Running $name in the foreground (Ctrl+C or type 'stop'/'end' to stop)\""
        echo "  exec $cmd"
      else
        echo "  nohup $cmd >logs/$name.log 2>&1 & sleep 3"
      fi
    done
    echo 'fi'
  } >"$INSTALL_DIR/start-all.sh"
  chmod +x "$INSTALL_DIR/start-all.sh"

  cat >"$INSTALL_DIR/stop-all.sh" <<'EOF'
#!/usr/bin/env bash
# Gracefully stops servers started by start-all.sh
S=minecraft_PLACEHOLDER
if command -v tmux >/dev/null 2>&1 && tmux has-session -t $S 2>/dev/null; then
  tmux send-keys -t $S:server "stop" Enter 2>/dev/null
  tmux send-keys -t $S:proxy "end" Enter 2>/dev/null
  tmux send-keys -t $S:backend "stop" Enter 2>/dev/null
  echo "Waiting for worlds to save..."; sleep 15
  tmux kill-session -t $S 2>/dev/null
elif command -v screen >/dev/null 2>&1; then
  for n in server backend; do screen -S mc-$n -X stuff "stop$(printf '\r')" 2>/dev/null; done
  screen -S mc-proxy -X stuff "end$(printf '\r')" 2>/dev/null
  sleep 15; screen -S mc-tunnel -X quit 2>/dev/null
fi
echo "Stopped."
EOF
  sedi "s/^S=minecraft_PLACEHOLDER$/S=$SESSION/" "$INSTALL_DIR/stop-all.sh"
  chmod +x "$INSTALL_DIR/stop-all.sh"
  if (( IS_MAC )); then   # double-clickable versions for Finder
    printf '#!/bin/bash\ncd "$(dirname "$0")" && ./start-all.sh --attach\necho; read -rp "Press Enter to close this window " _\n' >"$INSTALL_DIR/Start Server.command"
    printf '#!/bin/bash\ncd "$(dirname "$0")" && ./stop-all.sh\necho; read -rp "Press Enter to close this window " _\n' >"$INSTALL_DIR/Stop Server.command"
    chmod +x "$INSTALL_DIR/Start Server.command" "$INSTALL_DIR/Stop Server.command"
    xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
  fi
}

install_systemd() {
  command -v systemctl >/dev/null 2>&1 || { warn "systemd not found, skipping autostart."; return; }
  # Preferred: a systemd USER service (no root needed). "linger" lets it start at boot, before you log in.
  if systemctl --user show-environment >/dev/null 2>&1; then
    local ud="$HOME/.config/systemd/user"; mkdir -p "$ud"
    cat >"$ud/minecraft.service" <<EOF
[Unit]
Description=$SERVER_NAME (Minecraft server, mc-setup.sh)
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start-all.sh
ExecStop=$INSTALL_DIR/stop-all.sh
RemainAfterExit=yes
TimeoutStopSec=60

[Install]
WantedBy=default.target
EOF
    if systemctl --user daemon-reload && systemctl --user enable minecraft.service >/dev/null 2>&1; then
      ok "Autostart enabled (systemctl --user start|stop|status minecraft)"
    fi
    if command -v loginctl >/dev/null 2>&1 && ! loginctl enable-linger "$(id -un)" >/dev/null 2>&1; then
      if [[ -n "$SUDO" || $EUID -eq 0 ]]; then $SUDO loginctl enable-linger "$(id -un)" >/dev/null 2>&1 || true; fi
    fi
    return 0
  fi
  # Fallback: a normal system service (needs root or sudo)
  if [[ $EUID -ne 0 && -z "$SUDO" ]]; then warn "Autostart needs a systemd user session or administrator rights - skipping it."; return 0; fi
  local unit="/etc/systemd/system/minecraft.service"
  $SUDO tee "$unit" >/dev/null <<EOF
[Unit]
Description=$SERVER_NAME (Minecraft server, mc-setup.sh)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$(id -un)
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start-all.sh
ExecStop=$INSTALL_DIR/stop-all.sh
RemainAfterExit=yes
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
EOF
  if $SUDO systemctl daemon-reload && $SUDO systemctl enable minecraft.service >/dev/null 2>&1; then
    ok "Autostart enabled (systemctl start|stop|status minecraft)"
  fi
}

install_launchd() {   # macOS: start the server when you log in
  local label dir="$HOME/Library/LaunchAgents" plist esc="$INSTALL_DIR"
  label="com.mc-setup.$(server_session)"; plist="$dir/$label.plist"
  esc="${esc//&/&amp;}"; esc="${esc//</&lt;}"; esc="${esc//>/&gt;}"
  mkdir -p "$dir"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$esc/start-all.sh</string></array>
  <key>WorkingDirectory</key><string>$esc</string>
  <key>RunAtLoad</key><true/>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StandardOutPath</key><string>$esc/logs/launchd.log</string>
  <key>StandardErrorPath</key><string>$esc/logs/launchd.log</string>
</dict>
</plist>
EOF
  mkdir -p "$INSTALL_DIR/logs"
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$(id -u)" "$plist" >/dev/null 2>&1 || launchctl load -w "$plist" >/dev/null 2>&1; then
    ok "Autostart enabled: the server starts when you log in to this Mac"
    info "To turn it off: launchctl bootout gui/$(id -u)/$label   and delete $plist"
  else
    warn "Could not enable autostart. You can still start the server with 'Start Server.command'."
  fi
}

# ============================================================================
#  CUSTOMISATION  (asked before the summary; downloads only happen at install)
# ============================================================================
VIEW_DIST=10; SIM_DIST=10; LEVEL_TYPE="normal"; LEVEL_NAME="world"; PVP=true; CMD_BLOCKS=false
ALLOW_FLIGHT=false; HARDCORE=false; SPAWN_PROT=16; ALLOW_NETHER=true; GEN_STRUCT=true
SPAWN_ANIMALS=true; SPAWN_MONSTERS=true; SPAWN_NPCS=true; FORCE_GM=false; IDLE_TIMEOUT=0
RES_PACK_URL=""; RES_PACK_SHA1=""; RES_PACK_REQ=false; ICON_SRC=""; LOADER="none"; LOADER_VER=""
AUTORESTART=false; BACKUP_SCRIPT=false
BEDROCK=false; BEDROCK_PORT=19132; PUBLIC_ADDR_BE=""
SERVER_NAME="Minecraft Server"
MOD_ENTRIES=(); EXTRA_PROPS=(); OP_NAMES=(); WL_NAMES=(); MR_SEEN=()
MODRINTH="https://api.modrinth.com/v2"

Lf() {   # Lf "template with {0} {1}" args...  -> translated text with the values filled in
  local t i=0 a; t=$(L "$1"); shift
  for a in "$@"; do t="${t//"{$i}"/"$a"}"; i=$((i+1)); done
  builtin printf '%s' "$t"
}
ask_bool() {  # <varname> <question>
  local -n ref="$1"; local def=yes
  [[ "$ref" == "false" ]] && def=no
  if ui_yesno "$2" "$def"; then ref=true; else ref=false; fi
}
ask_num() {   # <varname> <question> <min> <max>
  local -n ref="$1"; local v
  v=$(ui_input "$2" "$ref")
  if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= $3 && v <= $4 )); then ref="$v"
  else ui_msg "$(Lf "Please enter a number from {0} to {1}. Kept: {2}" "$3" "$4" "$ref")"; fi
}
fetch_get() { local url="$1"; shift; curl -fsSL -G --retry 3 --connect-timeout 15 -A "$UA" "$@" "$url"; }

# ---- Server name -------------------------------------------------------------
customise_name() {
  local v old="$SERVER_NAME"
  v=$(ui_input "Name of your server (e.g. Creeper Cove).
Used for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list." "$SERVER_NAME")
  v="${v//\"/}"; v="${v//|/}"
  [[ -n "$v" ]] && SERVER_NAME="$v"
  if [[ "$MOTD" == "A Minecraft Server" || "$MOTD" == "$old" ]]; then MOTD="$SERVER_NAME"; fi
}

# ---- MOTD ------------------------------------------------------------------
customise_motd() {
  local v
  v=$(ui_input "Server list message (MOTD).

Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset
Use \\n for a second line.    Example: &6&lMy Server\\n&7Welcome!" "$MOTD")
  MOTD="${v//\"/}"
}

# ---- Icon ------------------------------------------------------------------
customise_icon() {
  local v
  v=$(ui_input "Server icon: path to an image (png/jpg/gif...) or an https:// link.
It is converted to 64x64 pixels automatically (centre-cropped to a square).
Leave empty for no icon." "$ICON_SRC")
  v="${v/#\~/$HOME}"
  if [[ -n "$v" && ! "$v" =~ ^https?:// && ! -f "$v" ]]; then ui_msg "$(Lf "File not found: {0}" "$v")"; return; fi
  ICON_SRC="$v"
}
convert_icon() {  # <src path|url> <dest png>
  local src="$1" dest="$2" tmp="" im=""
  if [[ "$src" =~ ^https?:// ]]; then
    tmp=$(mktemp "$STATE_DIR/icon.XXXXXX")
    curl -fsSL -A "$UA" -o "$tmp" "$src" || { warn "Could not download the icon."; return 1; }
    src="$tmp"
  fi
  have_im() { command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; }
  if ! have_im && ! python3 -c 'import PIL' >/dev/null 2>&1 && (( ! IS_MAC )); then
    pkg_install imagemagick >/dev/null 2>&1 || true
  fi
  if command -v magick >/dev/null 2>&1; then im=magick
  elif command -v convert >/dev/null 2>&1; then im=convert; fi
  if [[ -n "$im" ]]; then
    "$im" "${src}[0]" -resize 64x64^ -gravity center -extent 64x64 PNG32:"$dest"
  elif python3 -c 'import PIL' >/dev/null 2>&1; then
    python3 - "$src" "$dest" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
w, h = im.size; s = min(w, h); l = (w - s) // 2; t = (h - s) // 2
im.crop((l, t, l + s, t + s)).resize((64, 64), Image.LANCZOS).save(sys.argv[2], "PNG")
PY
  elif (( IS_MAC )) && command -v sips >/dev/null 2>&1; then   # built into macOS
    local w h m t2; t2=$(mktemp "$STATE_DIR/sips.XXXXXX")
    w=$(sips -g pixelWidth "$src" 2>/dev/null | awk '/pixelWidth/{print $2}'); h=$(sips -g pixelHeight "$src" 2>/dev/null | awk '/pixelHeight/{print $2}')
    [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || { warn "Could not read that image."; return 1; }
    m=$(( w < h ? w : h ))
    sips -s format png -c "$m" "$m" "$src" --out "$t2" >/dev/null 2>&1 && sips -z 64 64 "$t2" --out "$dest" >/dev/null 2>&1 \
      || { warn "Could not convert the icon."; return 1; }
    rm -f "$t2"
  else
    warn "Need ImageMagick or Python Pillow to convert the icon. Install one and re-run, or put a 64x64 server-icon.png in the server folder yourself."
    return 1
  fi
  ok "Server icon created (64x64)"
}

# ---- Mods / plugins ----------------------------------------------------------
mr_loaders() { if [[ "$SOFTWARE" == "paper" ]]; then echo '["paper","spigot","bukkit"]'; else echo "[\"$LOADER\"]"; fi; }
mr_search() {   # <query> -> Modrinth search JSON
  local facets   # plugins are listed on Modrinth as project type "mod" with a paper/spigot/bukkit category
  facets=$(jq -nc --arg v "$MC_VERSION" --argjson c "$(mr_loaders)" \
    '[["project_type:mod"],["versions:"+$v],($c|map("categories:"+.))]')
  fetch_get "$MODRINTH/search" --data-urlencode "query=$1" --data-urlencode "facets=$facets" --data-urlencode "limit=10"
}
mr_add_project() {   # <slug|id> [depth]   adds newest compatible file (+ required dependencies)
  local id="$1" depth="${2:-0}" vj v file dep
  if (( ${#MR_SEEN[@]} )) && [[ " ${MR_SEEN[*]} " == *" $id "* ]]; then return 0; fi
  MR_SEEN+=("$id")
  vj=$(fetch_get "$MODRINTH/project/$id/version" --data-urlencode "loaders=$(mr_loaders)" \
        --data-urlencode "game_versions=[\"$MC_VERSION\"]") || { warn "$(Lf "Modrinth lookup failed for '{0}'." "$id")"; return 1; }
  v=$(jq -c '.[0] // empty' <<<"$vj")
  if [[ -z "$v" && "$SOFTWARE" == "paper" ]]; then   # plugins often keep working on newer Minecraft: use the newest build
    vj=$(fetch_get "$MODRINTH/project/$id/version" --data-urlencode "loaders=$(mr_loaders)") || true
    v=$(jq -c '.[0] // empty' <<<"${vj:-[]}")
    [[ -n "$v" ]] && warn "$(Lf "'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work." "$id" "$MC_VERSION" "$(jq -r '.game_versions[-1] // "?"' <<<"$v")")"
  fi
  [[ -n "$v" ]] || { warn "$(Lf "'{0}' has no download for {1} on this loader." "$id" "$MC_VERSION")"; return 1; }
  file=$(jq -c '((.files|map(select(.primary))[0]) // .files[0])' <<<"$v")
  MOD_ENTRIES+=("$(jq -r '[.url, .filename, (.hashes.sha1 // "")] | join("|")' <<<"$file")")
  if (( depth < 2 )); then
    for dep in $(jq -r '.dependencies[]? | select(.dependency_type=="required" and .project_id!=null) | .project_id' <<<"$v"); do
      mr_add_project "$dep" $((depth + 1)) || true
    done
  fi
}
resolve_loader() {   # sets LOADER_VER for $LOADER + $MC_VERSION, returns 1 if unsupported
  local fv="" list prefix
  LOADER_VER=""
  case "$LOADER" in
    fabric)
      LOADER_VER=$(fetch "https://meta.fabricmc.net/v2/versions/loader/$MC_VERSION" 2>/dev/null | jq -r '[.[]|select(.loader.stable)][0].loader.version // empty' 2>/dev/null || true) ;;
    forge)
      if ver_ge "$MC_VERSION" "1.17"; then
        fv=$(fetch "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json" 2>/dev/null | jq -r --arg v "$MC_VERSION" '.promos[$v+"-recommended"] // .promos[$v+"-latest"] // empty' 2>/dev/null || true)
        [[ -n "$fv" ]] && LOADER_VER="$MC_VERSION-$fv"
      fi ;;
    neoforge)
      prefix="${MC_VERSION#1.}"; [[ "$prefix" != *.* ]] && prefix="$prefix.0"
      list=$(fetch "https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge" 2>/dev/null | jq -r '.versions[]' 2>/dev/null || true)
      LOADER_VER=$(grep -E "^${prefix//./\\.}\\." <<<"$list" | grep -v -- '-' | sort -V | tail -n1 || true) ;;
  esac
  [[ -n "$LOADER_VER" ]]
}
install_loader() {   # <server dir>   (needs JAVA_BIN)
  local d="$1" iv url argsf
  case "$LOADER" in
    fabric)
      iv=$(fetch "https://meta.fabricmc.net/v2/versions/installer" | jq -r '[.[]|select(.stable)][0].version')
      download "https://meta.fabricmc.net/v2/versions/loader/$MC_VERSION/$LOADER_VER/$iv/server/jar" "$d/fabric-server-launch.jar"
      LAUNCH="-jar fabric-server-launch.jar --nogui" ;;
    forge|neoforge)
      if [[ "$LOADER" == "forge" ]]; then url="https://maven.minecraftforge.net/net/minecraftforge/forge/$LOADER_VER/forge-$LOADER_VER-installer.jar"
      else url="https://maven.neoforged.net/releases/net/neoforged/neoforge/$LOADER_VER/neoforge-$LOADER_VER-installer.jar"; fi
      download "$url" "$d/installer.jar"
      spin_run "Running the $LOADER installer (a few minutes)" \
        bash -c 'cd "$1" && "$2" -jar installer.jar --installServer >installer.log 2>&1' _ "$d" "$JAVA_BIN" || die "$LOADER installer failed - see $d/installer.log"
      rm -f "$d/installer.jar" "$d/installer.jar.log"
      argsf=$(cd "$d" && find libraries -name unix_args.txt 2>/dev/null | head -n1)
      [[ -n "$argsf" ]] || die "Could not find the $LOADER launch arguments after install."
      LAUNCH="@$argsf --nogui" ;;
  esac
  ok "$LOADER $LOADER_VER installed"
}

catalog_load() {   # echo catalog lines (script table + optional plugins.list / mods.list)
  local kind="$1" f l dir
  if [[ "$kind" == "plugins" ]]; then printf '%s\n' "${PLUGIN_CATALOG[@]}"; else printf '%s\n' "${MOD_CATALOG[@]}"; fi
  for dir in "$(dirname "${BASH_SOURCE[0]}")" "$PWD"; do
    if [[ "$kind" == "plugins" ]]; then f="$dir/plugins.list"; else f="$dir/mods.list"; fi
    [[ -f "$f" ]] || continue
    while IFS= read -r l; do
      l="${l%%#*}"; [[ "$l" == *"|"* ]] && printf '%s\n' "$l"
    done <"$f"
  done
}
catalog_filter() {   # stdin: slug|Name|Desc lines -> same lines + |ok or |old (no build for this Minecraft version yet); wrong-platform ones are dropped
  local lines=() json res ids e slug st
  mapfile -t lines
  (( ${#lines[@]} )) || return 0
  ids=$(printf '%s\n' "${lines[@]}" | cut -d'|' -f1 | jq -R . | jq -sc .)
  json=$(fetch_get "$MODRINTH/projects" --data-urlencode "ids=$ids") || { for e in "${lines[@]}"; do printf '%s|ok\n' "$e"; done; return 0; }
  res=$(jq -r --arg v "$MC_VERSION" --argjson l "$(mr_loaders)" \
    '.[] | select(.loaders | any(. as $x | ($l | index($x)) != null)) | .slug + "\t" + (if (.game_versions | index($v)) != null then "ok" else "old" end)' <<<"$json")
  for e in "${lines[@]}"; do
    slug="${e%%|*}"
    st=$(awk -F'\t' -v s="$slug" '$1==s {print $2; exit}' <<<"$res")
    [[ -n "$st" ]] || continue
    printf '%s|%s\n' "$e" "$st"
  done
  return 0
}
mods_popular() {   # pick from the curated list
  local kind="$1" cat=() items=() e slug name desc st picks p nold=0
  info "$(Lf "Checking which popular {0} work with Minecraft {1} ..." "$(L "$kind")" "$MC_VERSION")"
  mapfile -t cat < <(catalog_load "$kind" | catalog_filter)
  for e in "${cat[@]}"; do
    IFS='|' read -r slug name desc st <<<"$e"
    if (( ${#MR_SEEN[@]} )) && [[ " ${MR_SEEN[*]} " == *" $slug "* ]]; then continue; fi
    if [[ "$st" == "old" ]]; then desc="$desc  $(Lf "[not updated for {0} yet - newest version will be tried]" "$MC_VERSION")"; nold=$((nold+1)); fi
    items+=("$slug" "$name - $desc")
  done
  if (( ${#items[@]} == 0 )); then ui_msg "You already added everything in the popular list. Try the search option for more."; return 0; fi
  if (( nold )); then ui_msg "$(Lf "Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try." "$MC_VERSION" "$nold")"; fi
  picks=$(ui_multi "$(Lf "Pick the {0} you want (Space = tick, Enter = done, A = all)" "$(L "$kind")")" "${items[@]}")
  for p in $picks; do mr_add_project "$p" && ok "$(Lf "Added {0}" "$p")"; done
  return 0
}

mods_pick_loader() {   # Vanilla only
  local c
  if [[ "$SETUP" == "velocity" ]]; then ui_msg "Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)"; return 1; fi
  c=$(ui_menu "Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):" "fabric" \
    "fabric"   "Fabric - lightweight, huge mod library (recommended)" \
    "neoforge" "NeoForge - big content mods (1.20.2+)" \
    "forge"    "Forge - classic loader (1.17+)" \
    "none"     "Plain Vanilla, no mods")
  [[ "$c" == "none" ]] && { LOADER=none; MOD_ENTRIES=(); MR_SEEN=(); return 1; }
  LOADER="$c"
  if ! resolve_loader; then
    ui_msg "$(Lf "{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version." "$LOADER" "$MC_VERSION")"
    LOADER=none; return 1
  fi
  MOD_ENTRIES=(); MR_SEEN=()
  [[ "$LOADER" == "fabric" ]] && { mr_add_project fabric-api || true; }
  return 0
}
customise_mods() {
  local kind="plugins" c q res rows=() items=() r slug title desc pick e i hdr
  if [[ "$SOFTWARE" == "vanilla" ]]; then
    kind="mods"
    if [[ "$LOADER" == "none" ]]; then mods_pick_loader || return 0; fi
  fi
  while true; do
    local kw; kw=$(L "$kind")
    if [[ $LOADER != none ]]; then hdr=$(Lf "Add {0}  ({1} queued, loader: {2})" "$kw" "${#MOD_ENTRIES[@]}" "$LOADER $LOADER_VER")
    else hdr=$(Lf "Add {0}  ({1} queued)" "$kw" "${#MOD_ENTRIES[@]}"); fi
    c=$(ui_menu "$hdr" "popular" \
      "popular" "$(Lf "Pick from a list of popular {0}" "$kw")" \
      "search" "$(Lf "Search Modrinth for {0} (compatible with {1})" "$kw" "$MC_VERSION")" \
      "url"    "Add direct https:// links to .jar files" \
      "list"   "$(Lf "Show / remove queued {0}" "$kw")" \
      "back"   "$(Lf "Done with {0}" "$kw")")
    case "$c" in
      back) return 0 ;;
      popular) mods_popular "$kind" ;;
      search)
        q=$(ui_input "$(Lf "Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms" "$kw" "$MC_VERSION")" "")
        [[ -z "$q" ]] && continue
        res=$(mr_search "$q") || { warn "Modrinth search failed."; continue; }
        mapfile -t rows < <(jq -r '.hits[] | [.slug, .title, (.description // "")] | @tsv' <<<"$res")
        if (( ${#rows[@]} == 0 )); then ui_msg "$(Lf "Nothing found for '{0}' that works with Minecraft {1}." "$q" "$MC_VERSION")"; continue; fi
        items=()
        for r in "${rows[@]}"; do
          IFS=$'\t' read -r slug title desc <<<"$r"
          items+=("$slug" "${title:0:22} - ${desc:0:38}")
        done
        items+=("cancel" "Back")
        pick=$(ui_menu "$(Lf "Results for '{0}':" "$q")" "${items[0]}" "${items[@]}")
        [[ "$pick" == "cancel" ]] && continue
        if mr_add_project "$pick"; then ui_msg "$(Lf "Added '{0}' (and any required dependencies)." "$pick")"; fi ;;
      url)
        q=$(ui_input "Direct https:// links to .jar files, separated by spaces.
Only use links from sources you trust - these files run on your server." "")
        for e in $q; do
          if [[ ! "$e" =~ ^https:// ]]; then warn "$(Lf "Skipping '{0}' (must start with https://)" "$e")"; continue; fi
          r="${e%%\?*}"; r="${r##*/}"
          [[ "$r" == *.jar ]] || r="download-$RANDOM.jar"
          MOD_ENTRIES+=("$e|$r|")
        done ;;
      list)
        if (( ${#MOD_ENTRIES[@]} == 0 )); then ui_msg "Nothing queued yet."; continue; fi
        items=(); i=0
        for e in "${MOD_ENTRIES[@]}"; do items+=("$i" "$(cut -d'|' -f2 <<<"$e")"); i=$((i+1)); done
        items+=("cancel" "Back (keep everything)")
        pick=$(ui_menu "Pick one to REMOVE from the install list:" "cancel" "${items[@]}")
        if [[ "$pick" != "cancel" ]]; then
          unset 'MOD_ENTRIES[pick]'; MOD_ENTRIES=("${MOD_ENTRIES[@]+"${MOD_ENTRIES[@]}"}")
        fi ;;
    esac
  done
}

# ---- Whitelist / ops ----------------------------------------------------------
parse_names() {   # "a, b c" -> one valid name per line
  local n
  for n in ${1//,/ }; do
    if [[ "$n" =~ ^[A-Za-z0-9_.]{3,16}$ ]]; then echo "$n"; else warn "$(Lf "Skipping invalid name '{0}'" "$n")" >&2; fi
  done
}
customise_players() {
  local v
  v=$(ui_input "Operators (admins). Minecraft usernames separated by spaces or commas.
Ops can use all commands." "${OP_NAMES[*]:-}")
  mapfile -t OP_NAMES < <(parse_names "$v")
  v=$(ui_input "Whitelist: only these players may join. Usernames separated by spaces or commas.
Leave empty to keep the whitelist as chosen earlier." "${WL_NAMES[*]:-}")
  mapfile -t WL_NAMES < <(parse_names "$v")
  (( ${#WL_NAMES[@]} )) && WHITELIST=true
  return 0
}
offline_uuid_raw() {   # <name> -> 32 hex chars (same as Minecraft's offline UUID)
  local h b8
  h=$(printf 'OfflinePlayer:%s' "$1" | md5sum | cut -d' ' -f1)
  b8=$(printf '%x' $(( (0x${h:16:1} & 3) | 8 )))
  printf '%s3%s%s%s' "${h:0:12}" "${h:13:3}" "$b8" "${h:17:15}"
}
player_uuid() {   # <name> -> dashed uuid
  local id
  if [[ "$ONLINE" == "true" ]]; then
    id=$(curl -fsS --max-time 10 -A "$UA" "https://api.mojang.com/users/profiles/minecraft/$1" 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
    [[ -n "$id" ]] || return 1
  else
    id=$(offline_uuid_raw "$1")
  fi
  printf '%s-%s-%s-%s-%s\n' "${id:0:8}" "${id:8:4}" "${id:12:4}" "${id:16:4}" "${id:20:12}"
}
write_player_lists() {   # <server dir>
  local n u wl='[]' ops='[]'
  if (( ${#WL_NAMES[@]} )); then
    for n in "${WL_NAMES[@]}"; do
      u=$(player_uuid "$n") || { warn "$(Lf "Could not look up '{0}' - add later with: whitelist add {0}" "$n")"; continue; }
      wl=$(jq -c --arg u "$u" --arg n "$n" '. + [{uuid:$u,name:$n}]' <<<"$wl")
    done
    jq . <<<"$wl" >"$1/whitelist.json"
  fi
  if (( ${#OP_NAMES[@]} )); then
    for n in "${OP_NAMES[@]}"; do
      u=$(player_uuid "$n") || { warn "$(Lf "Could not look up '{0}' - add later with: op {0}" "$n")"; continue; }
      ops=$(jq -c --arg u "$u" --arg n "$n" '. + [{uuid:$u,name:$n,level:4,bypassesPlayerLimit:false}]' <<<"$ops")
    done
    jq . <<<"$ops" >"$1/ops.json"
  fi
  return 0
}

# ---- World / gameplay / performance / extras -----------------------------------
customise_world() {
  LEVEL_TYPE=$(ui_menu "World type:" "$LEVEL_TYPE" \
    "normal" "Normal terrain" "flat" "Superflat" "large_biomes" "Large biomes" "amplified" "Amplified (tall mountains)")
  SEED=$(ui_input "World seed (empty = random):" "$SEED")
  local n; n=$(ui_input "World folder name:" "$LEVEL_NAME"); [[ "$n" =~ ^[A-Za-z0-9_.-]+$ ]] && LEVEL_NAME="$n"
  ask_bool GEN_STRUCT "Generate structures (villages, strongholds, ...)?"
  ask_bool ALLOW_NETHER "Allow the Nether?"
  ask_bool HARDCORE "Hardcore mode? (one life, forced hard difficulty)"
  return 0
}
customise_gameplay() {
  ask_bool PVP "Allow player-vs-player combat (PvP)?"
  ask_bool CMD_BLOCKS "Enable command blocks?"
  ask_bool ALLOW_FLIGHT "Allow flying (needed for some mods; otherwise flight is kicked)?"
  ask_bool SPAWN_ANIMALS "Spawn animals?"
  ask_bool SPAWN_MONSTERS "Spawn monsters?"
  ask_bool SPAWN_NPCS "Spawn villagers?"
  ask_bool FORCE_GM "Force everyone into the default game mode on every join?"
  ask_num SPAWN_PROT "Spawn protection radius in blocks (0 = off):" 0 200
  ask_num IDLE_TIMEOUT "Kick idle players after N minutes (0 = never):" 0 1440
  return 0
}
customise_perf() {
  ask_num VIEW_DIST "View distance in chunks (2-32). Lower = faster:" 2 32
  ask_num SIM_DIST "Simulation distance in chunks (2-32). Lower = faster:" 2 32
  return 0
}
customise_pack() {
  local v
  v=$(ui_input "Server resource pack: direct https:// link to a .zip (empty = none).
Players are offered it when they join. Its checksum is calculated at install time." "$RES_PACK_URL")
  if [[ -n "$v" && ! "$v" =~ ^https?:// ]]; then ui_msg "$(Lf "That is not a link. Kept: {0}" "${RES_PACK_URL:-$(L none)}")"; return 0; fi
  RES_PACK_URL="$v"
  [[ -n "$v" ]] && ask_bool RES_PACK_REQ "Kick players who decline the resource pack?"
  return 0
}
customise_extra() {
  local v kv
  v=$(ui_input "Any other server.properties setting as key=value, separated by spaces.
Example: rcon.port=25575 enable-status=true network-compression-threshold=512" "${EXTRA_PROPS[*]:-}")
  EXTRA_PROPS=()
  for kv in $v; do
    if [[ "$kv" =~ ^[a-z0-9.-]+=[^[:space:]]*$ ]]; then EXTRA_PROPS+=("$kv"); else warn "$(Lf "Skipping '{0}' (use key=value)" "$kv")"; fi
  done
  return 0
}
customise_maint() {
  ask_bool AUTORESTART "Restart the server automatically if it crashes?"
  ask_bool BACKUP_SCRIPT "Create a backup script (zips the world into the backups folder, keeps the newest 10)?"
  return 0
}

customise_menu() {
  local c="name"
  while true; do
    c=$(ui_menu "Customise your server. Pick a category; choose 'done' when finished." "$c" \
      "name"     "$(Lf "Server name: {0}" "$SERVER_NAME")" \
      "motd"     "$(Lf "Server list message with colours: {0}" "${MOTD:0:30}")" \
      "icon"     "$(Lf "Server icon: {0}" "${ICON_SRC:-$(L none)}")" \
      "mods"     "$(if [[ $SOFTWARE == paper ]]; then Lf "Plugins: {0} queued" "${#MOD_ENTRIES[@]}"; else Lf "Mods: {0} queued" "${#MOD_ENTRIES[@]}"; fi)" \
      "players"  "$(Lf "Operators ({0}) and whitelist ({1})" "${#OP_NAMES[@]}" "${#WL_NAMES[@]}")" \
      "world"    "World type, seed, structures, nether, hardcore" \
      "gameplay" "PvP, command blocks, flying, mobs, spawn protection" \
      "perf"     "$(Lf "View / simulation distance: {0} / {1}" "$VIEW_DIST" "$SIM_DIST")" \
      "pack"     "$(Lf "Resource pack: {0}" "${RES_PACK_URL:-$(L none)}")" \
      "extra"    "$(Lf "Any other server.properties setting ({0})" "${#EXTRA_PROPS[@]}")" \
      "maint"    "Auto-restart on crash, backup script" \
      "done"     "Finished customising")
    case "$c" in
      name) customise_name ;; motd) customise_motd ;; icon) customise_icon ;; mods) customise_mods ;;
      players) customise_players ;; world) customise_world ;; gameplay) customise_gameplay ;;
      perf) customise_perf ;; pack) customise_pack ;; extra) customise_extra ;;
      maint) customise_maint ;; done) return 0 ;;
    esac
  done
}

write_backup_script() {   # <server window name>
  local lv="$LEVEL_NAME" SESSION; SESSION=$(server_session)
  cat >"$INSTALL_DIR/backup.sh" <<EOF
#!/usr/bin/env bash
# Zips the world into ./backups and keeps the newest 10. Safe to run while the server is on.
cd "\$(dirname "\$0")"
mkdir -p backups
SAVED=""
if command -v tmux >/dev/null 2>&1 && tmux has-session -t $SESSION 2>/dev/null; then
  tmux send-keys -t $SESSION:$1 "save-off" Enter "save-all flush" Enter
  sleep 5; SAVED=1
fi
ITEMS=(); for d in "$lv" "${lv}_nether" "${lv}_the_end"; do [ -e "$SRV_DIR/\$d" ] && ITEMS+=("\$d"); done
tar czf "backups/world-\$(date +%Y%m%d-%H%M%S).tar.gz" -C "$SRV_DIR" "\${ITEMS[@]}" 2>/dev/null || true
[[ -n "\$SAVED" ]] && tmux send-keys -t $SESSION:$1 "save-on" Enter
ls -1t backups/world-*.tar.gz 2>/dev/null | tail -n +11 | while read -r f; do rm -f -- "\$f"; done
echo "Backup done: \$(ls -1t backups | head -n1)"
EOF
  chmod +x "$INSTALL_DIR/backup.sh"
}

# ============================================================================
#  THE WIZARD
# ============================================================================
need_cmd curl
need_cmd jq
need_cmd tar



# ----------------------------------------------------------------------------
#  Where to put the server
# ----------------------------------------------------------------------------
user_dir() {   # <DESKTOP|DOCUMENTS> <fallback>
  local d=""
  if command -v xdg-user-dir >/dev/null 2>&1; then d=$(xdg-user-dir "$1" 2>/dev/null || true); fi
  [[ -z "$d" || "$d" == "$HOME" ]] && d="$2"
  printf '%s' "$d"
}
folder_name() {   # server name -> safe folder name (spaces become dashes)
  local n="$1"
  n=$(printf '%s' "$n" | tr -d '/\\:*?"<>|' | tr -s ' ' '-' | sed -E 's/^[-. ]+//; s/[-. ]+$//')
  printf '%s' "${n:-minecraft-server}"
}
choose_install_dir() {   # sets INSTALL_DIR
  local here c base other fname full again
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
  # a downloaded script that macOS "translocated" lives in a temporary read-only folder: do not offer that
  if [[ -z "$here" || "$here" == /dev/* || "$here" == /proc/* || "$here" == */AppTranslocation/* || ! -w "$here" ]]; then here="$PWD"; fi
  [[ -w "$here" ]] || here="$HOME"
  fname=$(folder_name "$SERVER_NAME")
  while true; do
    local other_label="Somewhere else (type a folder)"; (( IS_MAC )) && other_label="Somewhere else (browse or type a folder)"
    local mitems=("here" "$(L "Next to this script (recommended)")  -  ${here/#$HOME/\~}")
    if (( IS_MAC )) || [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" || -d "$HOME/Desktop" ]]; then
      mitems+=("desktop" "On my Desktop" "documents" "In my Documents folder")
    fi
    mitems+=("home" "$(L "In my home folder")  -  ~/" "other" "$other_label")
    c=$(ui_menu "Where should your server be saved? A new folder with your server's name is created there." "here" "${mitems[@]}")
    case "$c" in
      here)      base="$here" ;;
      home)      base="$HOME" ;;
      desktop)   base=$(user_dir DESKTOP "$HOME/Desktop") ;;
      documents) base=$(user_dir DOCUMENTS "$HOME/Documents") ;;
      other)
        other=""
        if (( IS_MAC )) && command -v osascript >/dev/null 2>&1; then   # Finder folder picker (the picker is cancelled -> type it instead)
          other=$(osascript -e 'POSIX path of (choose folder with prompt "Where should the server folder be created?")' 2>/dev/null || true)
        fi
        if [[ -z "$other" ]]; then
          other=$(ui_input "Type the folder to put it in (it is created if it does not exist). Example: $HOME/games" "$HOME")
        fi
        other="${other/#\~/$HOME}"; base="${other:-$HOME}" ;;
    esac
    full="${base%/}/$fname"
    if ! mkdir -p "$base" 2>/dev/null || [[ ! -w "$base" ]]; then
      warn "Cannot write to $base. Please pick another place."; continue
    fi
    if [[ -d "$full" && -n "$(ls -A "$full" 2>/dev/null)" ]]; then
      again=$(ui_menu "A folder already exists at ${full/#$HOME/\~} and is not empty. If it holds a server, its worlds are kept but start files and settings are replaced." "other" \
        "other"    "Pick another place" \
        "continue" "Use it anyway")
      [[ "$again" == "other" ]] && continue
    else
      again=$(ui_menu "Your server will be installed in:
${full/#$HOME/\~}" "ok" \
        "ok"    "Yes, use this folder" \
        "other" "No, pick another place")
      [[ "$again" == "other" ]] && continue
    fi
    INSTALL_DIR="$full"; return 0
  done
}

# ============================================================================
#  Customise an existing server (mc-customize.sh runs this: mc-setup.sh --customize)
# ============================================================================
prop_get() { sed -n "s/^${2//./\\.}=//p" "$1" 2>/dev/null | head -n1; }   # <file> <key>
prop_set() {   # <file> <key> <value>
  local f="$1" k="$2" v="$3" esc
  if grep -q "^${k//./\\.}=" "$f" 2>/dev/null; then
    esc=$(printf '%s' "$v" | sed -e 's/[\\&|]/\\&/g')
    sedi "s|^${k//./\\.}=.*|${k}=${esc}|" "$f"
  else printf '%s=%s\n' "$k" "$v" >>"$f"; fi
}
PROP_MAP="MAX_PLAYERS:max-players GAMEMODE:gamemode FORCE_GM:force-gamemode DIFFICULTY:difficulty HARDCORE:hardcore PVP:pvp VIEW_DIST:view-distance SIM_DIST:simulation-distance SPAWN_PROT:spawn-protection CMD_BLOCKS:enable-command-block ALLOW_FLIGHT:allow-flight ALLOW_NETHER:allow-nether GEN_STRUCT:generate-structures SPAWN_ANIMALS:spawn-animals SPAWN_MONSTERS:spawn-monsters SPAWN_NPCS:spawn-npcs IDLE_TIMEOUT:player-idle-timeout LEVEL_NAME:level-name SEED:level-seed RES_PACK_URL:resource-pack RES_PACK_SHA1:resource-pack-sha1 RES_PACK_REQ:require-resource-pack"
props_load() {   # <server.properties> -> the settings variables
  local f="$1" m var key val
  [[ -f "$f" ]] || return 0
  for m in $PROP_MAP; do
    var="${m%%:*}"; key="${m#*:}"
    if grep -q "^${key//./\\.}=" "$f"; then val=$(prop_get "$f" "$key"); printf -v "$var" '%s' "$val"; fi
  done
  val=$(prop_get "$f" level-type); val="${val//\\/}"; val="${val#minecraft:}"; [[ -n "$val" ]] && LEVEL_TYPE="$val"
  val=$(prop_get "$f" motd); [[ -n "$val" ]] && MOTD=$(printf '%s' "$val" | sed -E 's/\\u00[aA]7/\&/g')
  WHITELIST=$(prop_get "$f" white-list); WHITELIST="${WHITELIST:-false}"
  return 0
}
props_save() {   # <server dir>: write the settings variables back, leaving every other line alone
  local f="$1/server.properties" m var key kv
  [[ -f "$f" ]] || return 0
  for m in $PROP_MAP; do var="${m%%:*}"; key="${m#*:}"; [[ -n "${!var+x}" ]] && prop_set "$f" "$key" "${!var}"; done
  prop_set "$f" motd "$(motd_props "$MOTD")"
  prop_set "$f" level-type "minecraft\\:${LEVEL_TYPE}"
  prop_set "$f" white-list "$WHITELIST"; prop_set "$f" enforce-whitelist "$WHITELIST"
  if (( ${#EXTRA_PROPS[@]} )); then for kv in "${EXTRA_PROPS[@]}"; do prop_set "$f" "${kv%%=*}" "${kv#*=}"; done; fi
  return 0
}
conf_set() {   # <key> <value>  in mc-setup.conf
  local f="$INSTALL_DIR/mc-setup.conf"
  [[ -f "$f" ]] || : >"$f"
  sedi "/^$1=/d" "$f"; printf '%s=%s\n' "$1" "$2" >>"$f"
}
backup_server() {   # <label>  -> zips the whole server folder into backups/ first
  local ts dest; ts=$(date +%Y%m%d-%H%M%S); mkdir -p "$INSTALL_DIR/backups"
  dest="$INSTALL_DIR/backups/${1}-${ts}.tar.gz"
  info "Making a backup first ..."
  if tar czf "$dest" --exclude='./backups' -C "$INSTALL_DIR" "$(basename "$SRV_DIR")" 2>/dev/null; then ok "$(Lf "Backup saved: {0}" "${dest/#$HOME/\~}")"
  else warn "The backup failed - stopping here so nothing is lost."; return 1; fi
}
rewrite_start() {   # rebuild start.sh for the current software/version/RAM
  local xms flags launch="-jar server.jar --nogui"
  if [[ "$LOADER" != "none" ]]; then flags="-XX:+UseG1GC"; xms=$(( RAM_MB / 2 ))
    if [[ "$LOADER" == "fabric" ]]; then launch="-jar fabric-server-launch.jar --nogui"
    else launch=$(sed -n 's/.*\(@[^ ]*args.txt\) --nogui.*/\1 --nogui/p' "$SRV_DIR/start.sh" | head -n1); fi
    [[ -z "$launch" ]] && return 0
  elif [[ "$SOFTWARE" == "paper" ]]; then flags="$AIKAR_FLAGS -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"; xms=$(( RAM_MB >= 2048 ? RAM_MB : RAM_MB / 2 ))
  else flags="-XX:+UseG1GC"; xms=$(( RAM_MB / 2 )); fi
  write_start_script "$SRV_DIR" "$JAVA_BIN" "$RAM_MB" "$xms" "$flags" "$launch"
}
find_servers() {   # prints the folders that hold an mc-setup.conf
  local r
  for r in "$(dirname "${BASH_SOURCE[0]}")" "$PWD" "$HOME/Desktop" "$HOME/Documents" "$HOME"; do
    find "$r" -maxdepth 3 -name mc-setup.conf 2>/dev/null
  done | while IFS= read -r cf; do dirname "$cf"; done | awk '!s[$0]++'
}
pick_server() {   # [folder]  sets INSTALL_DIR
  local found=() d items=() choice
  if [[ -n "${1:-}" ]]; then INSTALL_DIR="$1"; return 0; fi
  mapfile -t found < <(find_servers)
  for d in "${found[@]}"; do items+=("$d" "$(sed -n 's/^SERVER_NAME=//p' "$d/mc-setup.conf" | head -n1)   ${d/#$HOME/\~}"); done
  items+=("other" "Pick another folder ...")
  choice=$(ui_menu "Which server do you want to change?" "${items[0]}" "${items[@]}")
  if [[ "$choice" == "other" ]]; then
    choice=""
    if (( IS_MAC )) && command -v osascript >/dev/null 2>&1; then   # Finder folder picker
      choice=$(osascript -e 'POSIX path of (choose folder with prompt "Choose your server folder")' 2>/dev/null || true); choice="${choice%/}"
    fi
    [[ -z "$choice" ]] && choice=$(ui_input "Type the folder of your server (the one that contains start-all):" "")
    choice="${choice/#\~/$HOME}"
  fi
  [[ -f "$choice/mc-setup.conf" || -d "$choice/server" ]] || die "That folder does not look like a server made by this tool."
  INSTALL_DIR="$choice"
}
load_server() {   # reads mc-setup.conf, server.properties, ops and whitelist
  local c="$INSTALL_DIR/mc-setup.conf" k v
  for k in SERVER_NAME SOFTWARE LOADER MC_VERSION SETUP ONLINE RAM_MB PORT NET TUNNEL JAVA_BIN BEDROCK BEDROCK_PORT; do
    v=$(sed -n "s/^$k=//p" "$c" 2>/dev/null | head -n1 || true); [[ -n "$v" ]] && printf -v "$k" '%s' "$v"
  done
  PUBLIC_ADDR=$(sed -n 's/^PUBLIC_ADDRESS=//p' "$c" 2>/dev/null | head -n1 || true)
  PUBLIC_ADDR_BE=$(sed -n 's/^PUBLIC_ADDRESS_BEDROCK=//p' "$c" 2>/dev/null | head -n1 || true)
  SOFTWARE="${SOFTWARE:-paper}"; SETUP="${SETUP:-standalone}"; PORT="${PORT:-25565}"; RAM_MB="${RAM_MB:-2048}"
  if [[ "$SETUP" == "velocity" ]]; then SRV_DIR="$INSTALL_DIR/backend"; SRV_WIN=backend; else SRV_DIR="$INSTALL_DIR/server"; SRV_WIN=server; fi
  [[ -d "$SRV_DIR" ]] || die "I can not find the server folder inside $INSTALL_DIR."
  MOD_DIR=plugins; [[ "$LOADER" != "none" ]] && MOD_DIR=mods
  [[ -x "${JAVA_BIN:-}" ]] || JAVA_BIN=$(command -v java || true)
  if grep -q 'while true' "$SRV_DIR/start.sh" 2>/dev/null; then AUTORESTART=true; fi
  if [[ -f "$INSTALL_DIR/backup.sh" ]]; then BACKUP_SCRIPT=true; fi
  props_load "$SRV_DIR/server.properties"
  OP_NAMES=(); WL_NAMES=()
  if command -v jq >/dev/null 2>&1; then
    if [[ -f "$SRV_DIR/ops.json" ]]; then mapfile -t OP_NAMES < <(jq -r '.[].name' "$SRV_DIR/ops.json" 2>/dev/null || true); fi
    if [[ -f "$SRV_DIR/whitelist.json" ]]; then mapfile -t WL_NAMES < <(jq -r '.[].name' "$SRV_DIR/whitelist.json" 2>/dev/null || true); fi
  fi
  ICON_SRC=""; MOD_ENTRIES=(); MR_SEEN=(); EXTRA_PROPS=()
  return 0
}
place_queued() {   # download everything queued in the Add menu
  local e m_url m_name m_sha
  (( ${#MOD_ENTRIES[@]} )) || return 0
  mkdir -p "$SRV_DIR/$MOD_DIR"
  for e in "${MOD_ENTRIES[@]}"; do
    IFS='|' read -r m_url m_name m_sha <<<"$e"; m_name="${m_name##*/}"
    download "$m_url" "$SRV_DIR/$MOD_DIR/$m_name"; verify_hash "$SRV_DIR/$MOD_DIR/$m_name" sha1 "$m_sha"
  done
  ok "$(Lf "{0} file(s) placed in {1}" "${#MOD_ENTRIES[@]}" "$SRV_DIR/$MOD_DIR")"
  MOD_ENTRIES=(); MR_SEEN=()
}
remove_installed() {
  local jars=() f items=() picks p
  while IFS= read -r f; do jars+=("$f"); done < <(find "$SRV_DIR/$MOD_DIR" -maxdepth 1 -name '*.jar' 2>/dev/null | sort)
  if (( ${#jars[@]} == 0 )); then ui_msg "Nothing is installed in this folder yet."; return 0; fi
  for f in "${jars[@]}"; do items+=("$(basename "$f")" "$(basename "$f")"); done
  picks=$(ui_multi "Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)" "${items[@]}")
  mkdir -p "$SRV_DIR/$MOD_DIR/removed"
  for p in $picks; do mv -f "$SRV_DIR/$MOD_DIR/$p" "$SRV_DIR/$MOD_DIR/removed/" && ok "$(Lf "Removed {0}" "$p")"; done
  return 0
}
customise_version() {
  local list=() new req old
  info "Fetching version list ..."
  if [[ "$SOFTWARE" == "paper" && "$LOADER" == "none" ]]; then mapfile -t list < <(paper_versions); else mapfile -t list < <(vanilla_versions); fi
  [[ -n "${list[0]:-}" ]] || { warn "Could not get the version list (is the internet working?)."; return 0; }
  new=$(pick_version "Minecraft" "${list[@]}")
  [[ "$new" == "$MC_VERSION" ]] && { ui_msg "That is the version you already have."; return 0; }
  ui_yesno "$(Lf "Change Minecraft from {0} to {1}?

Worlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards." "$MC_VERSION" "$new")" no || return 0
  backup_server "before-$new" || return 0
  old="$MC_VERSION"; MC_VERSION="$new"
  req=$(java_for_mc "$MC_VERSION"); JAVA_BIN=$(ensure_java "$req")
  if [[ "$LOADER" != "none" ]]; then
    if ! resolve_loader; then warn "This loader has no release for that version."; MC_VERSION="$old"; return 0; fi
    install_loader "$SRV_DIR"
  elif [[ "$SOFTWARE" == "paper" ]]; then download_papermc paper "$MC_VERSION" "$SRV_DIR/server.jar"
  else download_vanilla "$MC_VERSION" "$SRV_DIR/server.jar"; fi
  rewrite_start
  conf_set MC_VERSION "$MC_VERSION"; conf_set JAVA_BIN "$JAVA_BIN"
  ok "$(Lf "Now on Minecraft {0}" "$MC_VERSION")"
  ui_msg "If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder."
  return 0
}
customise_bedrock() {
  local dis="$SRV_DIR/plugins/removed"
  if [[ "$BEDROCK" == true ]]; then
    ui_yesno "Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)" no || return 0
    mkdir -p "$dis"; mv -f "$SRV_DIR"/plugins/Geyser-Spigot.jar "$SRV_DIR"/plugins/floodgate-spigot.jar "$dis/" 2>/dev/null || true
    BEDROCK=false; conf_set BEDROCK false; ok "Bedrock support turned off."; return 0
  fi
  if [[ "$SETUP" == "velocity" || "$LOADER" != "none" ]]; then ui_msg "Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge)."; return 0; fi
  ui_yesno "$(Lf "Let Bedrock players (phones, consoles, Windows 10/11) join too?

Geyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used." "$BEDROCK_PORT")" yes || return 0
  if [[ "$SOFTWARE" != "paper" ]]; then
    ui_yesno "Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first." yes || return 0
    backup_server "before-paper" || return 0
    JAVA_BIN=$(ensure_java "$(java_for_mc "$MC_VERSION")")
    download_papermc paper "$MC_VERSION" "$SRV_DIR/server.jar" || { warn "PaperMC has no build for this version."; return 0; }
    SOFTWARE=paper; conf_set SOFTWARE paper; rewrite_start
  fi
  BEDROCK=true; install_geyser "$SRV_DIR"; conf_set BEDROCK true; conf_set BEDROCK_PORT "$BEDROCK_PORT"
  open_firewall "$BEDROCK_PORT" udp || true
  ui_msg "$(Lf "Bedrock players need UDP port {0} reachable. With playit.gg run  bash mc-setup.sh --tunnel-guide  to add the Bedrock tunnel; with a router, forward UDP {0} too." "$BEDROCK_PORT")"
  return 0
}
customise_existing() {
  local c pw
  pick_server "${1:-}"; load_server
  ui_msg "Tip: stop the server first (type  stop  in its window). Changes are read when it starts."
  while true; do
    c=$(ui_menu "What do you want to change?" "name" \
      "name"     "$(Lf "Server name: {0}" "$SERVER_NAME")" \
      "motd"     "$(Lf "Server list message with colours: {0}" "${MOTD:0:30}")" \
      "icon"     "Server icon" \
      "mods"     "$(if [[ $SOFTWARE == paper ]]; then L "Add plugins"; else L "Add mods"; fi)" \
      "remove"   "$(if [[ $SOFTWARE == paper ]]; then L "Remove plugins"; else L "Remove mods"; fi)" \
      "players"  "$(Lf "Operators ({0}) and whitelist ({1})" "${#OP_NAMES[@]}" "${#WL_NAMES[@]}")" \
      "world"    "World type, seed, structures, nether, hardcore" \
      "gameplay" "PvP, command blocks, flying, mobs, spawn protection" \
      "perf"     "$(Lf "View / simulation distance: {0} / {1}" "$VIEW_DIST" "$SIM_DIST")" \
      "pack"     "$(Lf "Resource pack: {0}" "${RES_PACK_URL:-$(L none)}")" \
      "extra"    "Any other server.properties setting" \
      "maint"    "Auto-restart on crash, backup script" \
      "version"  "$(Lf "Change the Minecraft version (now {0})" "$MC_VERSION")" \
      "bedrock"  "$(if [[ $BEDROCK == true ]]; then L "Bedrock players: ON (Geyser + Floodgate)"; else L "Bedrock players: off"; fi)" \
      "backup"   "Make a backup now" \
      "done"     "Finished customising")
    case "$c" in
      name)   customise_name; conf_set SERVER_NAME "$SERVER_NAME"; props_save "$SRV_DIR" ;;
      motd)   customise_motd; props_save "$SRV_DIR" ;;
      icon)   customise_icon
              if [[ -n "$ICON_SRC" ]]; then
                if [[ "$SETUP" == "velocity" ]]; then convert_icon "$ICON_SRC" "$INSTALL_DIR/proxy/server-icon.png" || true
                else convert_icon "$ICON_SRC" "$SRV_DIR/server-icon.png" || true; fi
              fi ;;
      mods)   customise_mods; place_queued ;;
      remove) remove_installed ;;
      players) customise_players
              if (( ${#WL_NAMES[@]} )); then WHITELIST=true; fi
              rm -f "$SRV_DIR/ops.json" "$SRV_DIR/whitelist.json"; write_player_lists "$SRV_DIR"; props_save "$SRV_DIR" ;;
      world)  customise_world; props_save "$SRV_DIR"
              ui_msg "Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is." ;;
      gameplay) customise_gameplay; props_save "$SRV_DIR" ;;
      perf)   customise_perf; props_save "$SRV_DIR" ;;
      pack)   customise_pack
              if [[ -n "$RES_PACK_URL" ]]; then
                pw=$(mktemp "$STATE_DIR/pack.XXXXXX")
                if curl -fsSL -A "$UA" -o "$pw" "$RES_PACK_URL"; then RES_PACK_SHA1=$(hash_file sha1 "$pw"); else warn "Could not download the resource pack - skipping it."; RES_PACK_URL=""; RES_PACK_SHA1=""; fi
                rm -f "$pw"
              else RES_PACK_SHA1=""; fi
              props_save "$SRV_DIR" ;;
      extra)  customise_extra; props_save "$SRV_DIR" ;;
      maint)  customise_maint; rewrite_start
              if [[ "$BACKUP_SCRIPT" == true ]]; then write_backup_script "$SRV_WIN"; else rm -f "$INSTALL_DIR/backup.sh"; fi ;;
      version) customise_version ;;
      bedrock) customise_bedrock ;;
      backup) backup_server "manual" || true ;;
      done)   break ;;
    esac
    ok "Saved."
  done
  ui_msg "All done. Start (or restart) your server to use the changes."
  exit 0
}

ask_bedrock() {   # <simple|advanced>  sets BEDROCK (and switches to Paper when needed)
  BEDROCK=false
  [[ "${SETUP:-standalone}" == "velocity" ]] && return 0
  local q
  if [[ "$1" == simple ]]; then
    q="Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?

They join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve)."
  else
    q="Also let Bedrock players join (Geyser + Floodgate)?

Bedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve)."
  fi
  if ui_yesno "$q" no; then
    BEDROCK=true
    if [[ "${SOFTWARE:-paper}" != "paper" ]]; then SOFTWARE=paper; ui_msg "Switched to the Standard (PaperMC) server, because Bedrock support needs it."; fi
  fi
  return 0
}

simple_setup() {
  local total v list
  v=$(ui_input "What do you want to call your server?" "My Minecraft Server")
  v="${v//\"/}"; v="${v//|/}"; SERVER_NAME="${v:-My Minecraft Server}"; MOTD="$SERVER_NAME"
  choose_install_dir
  SOFTWARE=$(ui_menu "Which kind of server do you want?" "paper" \
    "paper"   "Standard (recommended) - fast, and you can add plugins later" \
    "vanilla" "Pure Minecraft - exactly like the official game")
  ask_bedrock simple
  NET=$(ui_menu "How will your friends join?" "tunnel" \
    "tunnel"  "Over the internet - easiest, no router settings (free)" \
    "portfwd" "Over the internet using my router (port forwarding)" \
    "lan"     "Only people on my home Wi-Fi")
  if ui_yesno "Does everyone who will join own Minecraft (a paid Microsoft account)?

YES = safest, recommended.
NO  = anyone can join with any name (only for friends you trust)." yes; then ONLINE=true; else ONLINE=false; fi
  info "Finding the newest version ..."
  if [[ "$SOFTWARE" == "paper" ]]; then mapfile -t list < <(paper_versions); else mapfile -t list < <(vanilla_versions); fi
  [[ -n "${list[0]:-}" ]] || die "Could not get the version list (is the internet working?)."
  MC_VERSION=$(pick_version "Minecraft" "${list[@]}")
  SETUP=standalone; WHITELIST=false; PORT=25565; BACKEND_PORT=25566; MAX_PLAYERS=20
  GAMEMODE=survival; DIFFICULTY=normal; SEED=""; AUTOSTART=no
  TUNNEL=none; NGROK_TOKEN=""; DO_UPNP=no; DO_FIREWALL=no
  total=$(mem_mb)
  RAM_MB=$(( total / 2 / 1024 * 1024 )); (( RAM_MB > 4096 )) && RAM_MB=4096; (( RAM_MB < 1024 )) && RAM_MB=1024
  case "$NET" in
    tunnel)  TUNNEL=playit ;;
    portfwd) DO_UPNP=yes; DO_FIREWALL=yes ;;
    lan)     DO_FIREWALL=yes ;;
  esac
  ui_yesno "Want to change more things (server message, icon, mods, whitelist, world...)?

Most people choose No - you can still do that later." no && customise_menu
  return 0
}

banner
pick_language() {
  local def code c
  if [[ -n "${MCS_LANG:-}" ]]; then code=$(lang_from_locale)
  else
    def=$(lang_from_locale)
    code=$(ui_menu "Language / 语言 / भाषा / اللغة / שפה" "$def" \
      en "English" zh "中文" hi "हिन्दी" ar "العربية" he "עברית" es "Español" fr "Français" de "Deutsch" \
      pt "Português" ru "Русский" ja "日本語" ko "한국어" tr "Türkçe" it "Italiano")
  fi
  lang_load "$code"   # so the warning below is already in the chosen language
  case "$code" in zh|ja|ko|hi|ar|he|ru)
    if (( ! UTF )); then
      c=$(ui_menu "This terminal is not set to UTF-8, so this language may look broken (squares or ?). Continue in English instead?" "en" \
        "en" "Use English" "try" "Try it anyway")
      [[ "$c" == "en" ]] && { code=en; lang_load en; }
    elif [[ "$code" =~ ^(zh|ja|ko|hi|ar|he)$ ]]; then
      info "Tip: if you see squares instead of letters, run again with  --lang en  or use a terminal with a font that supports this language."
    fi ;;
  esac
}
pick_language
if [[ "${1:-}" == "--customize" || "${1:-}" == "--customise" ]]; then customise_existing "${2:-}"; fi
if [[ "${1:-}" == "--tunnel-guide" ]]; then   # just the playit.gg guide, for a server that is already installed
  PORT=25565; INSTALL_DIR="${2:-}"
  if [[ -z "$INSTALL_DIR" ]]; then   # find the newest server folder made by this script
    for r in "$(dirname "${BASH_SOURCE[0]}")" "$PWD" "$HOME/Desktop" "$HOME/Documents" "$HOME"; do
      f=$(find "$r" -maxdepth 3 -name mc-setup.conf 2>/dev/null | while IFS= read -r cf; do printf '%s\t%s\n' "$(file_mtime "$cf")" "$(dirname "$cf")"; done | sort -rn | head -n1 | cut -f2- || true)
      [[ -n "$f" ]] && { INSTALL_DIR="$f"; break; }
    done
    INSTALL_DIR="${INSTALL_DIR:-$HOME/minecraft-server}"
  fi
  if [[ -f "$INSTALL_DIR/mc-setup.conf" ]]; then
    PORT=$(sed -n 's/^PORT=//p' "$INSTALL_DIR/mc-setup.conf" | head -n1); PORT="${PORT:-25565}"
    PUBLIC_ADDR=$(sed -n 's/^PUBLIC_ADDRESS=//p' "$INSTALL_DIR/mc-setup.conf" | head -n1)
    PUBLIC_ADDR_BE=$(sed -n 's/^PUBLIC_ADDRESS_BEDROCK=//p' "$INSTALL_DIR/mc-setup.conf" | head -n1)
    [[ "$(sed -n 's/^BEDROCK=//p' "$INSTALL_DIR/mc-setup.conf" | head -n1)" == true ]] && BEDROCK=true
    BEDROCK_PORT=$(sed -n 's/^BEDROCK_PORT=//p' "$INSTALL_DIR/mc-setup.conf" | head -n1); BEDROCK_PORT="${BEDROCK_PORT:-19132}"
  fi
  printf '%s%s%s  %sPlayit.gg tunnel guide%s\n' "$C_GRAY" "$S_TOP" "$C_RESET" "$C_BOLD" "$C_RESET" >&2; bar_line
  tunnel_guide
  if [[ -f "$INSTALL_DIR/mc-setup.conf" ]]; then
    sedi '/^PUBLIC_ADDRESS/d' "$INSTALL_DIR/mc-setup.conf"; { echo "PUBLIC_ADDRESS=$PUBLIC_ADDR"; echo "PUBLIC_ADDRESS_BEDROCK=$PUBLIC_ADDR_BE"; } >>"$INSTALL_DIR/mc-setup.conf"
  fi
  printf '%s%s%s  Done.\n' "$C_GREEN" "$S_END" "$C_RESET" >&2
  exit 0
fi
printf '%s%s%s  %s%s%s\n' "$C_GREEN" "$S_TOP" "$C_RESET" "$C_BOLD" "$(L "Let's set up your Minecraft server")" "$C_RESET" >&2
if (( FANCY )); then say "${C_DIM}$(L "Use the arrow keys and Enter. Press Ctrl+C at any time to quit.")${C_RESET}"
else say "${C_DIM}Type a number and press Enter (Enter alone picks the suggested answer).${C_RESET}"; fi
say "${C_DIM}$(L "Nothing is installed until you confirm at the end.")${C_RESET}"
[[ $EUID -eq 0 ]] && warn "You are running as root. It works, but a normal user is safer for game servers."
bar_line

MODE=$(ui_menu "How do you want to set up?" "simple" \
  "simple"   "Simple - a few easy questions, everything else is chosen for you" \
  "advanced" "Advanced - choose every option yourself")

if [[ "$MODE" == "simple" ]]; then
  simple_setup
else
v=$(ui_input "What do you want to call your server?" "Minecraft Server")
v="${v//\"/}"; v="${v//|/}"; [[ -n "$v" ]] && SERVER_NAME="$v"
choose_install_dir

# --- Software ---------------------------------------------------------------
SOFTWARE=$(ui_menu "Which server software?" "paper" \
  "paper"   "PaperMC - faster, supports plugins (recommended)" \
  "vanilla" "Vanilla - the official Mojang server, no plugins")

# --- Proxy ------------------------------------------------------------------
SETUP=$(ui_menu "Normal server or Velocity proxy?

Velocity is a proxy that sits in front of your server. Useful if you plan to link several servers (lobby, survival, minigames) later." "standalone" \
  "standalone" "Normal - one server, players connect directly" \
  "velocity"   "Velocity proxy + Paper backend server")

if [[ "$SETUP" == "velocity" && "$SOFTWARE" == "vanilla" ]]; then
  if ui_yesno "Velocity needs a PaperMC backend (Vanilla cannot receive the player info Velocity forwards securely).

Switch the backend to PaperMC?" yes; then SOFTWARE="paper"
  else SETUP="standalone"; fi
fi

ask_bedrock advanced
if [[ "$SETUP" == "velocity" ]]; then BEDROCK=false; fi

info "Fetching version list ..."
if [[ "$SOFTWARE" == "paper" ]]; then
  mapfile -t VERS < <(paper_versions)
  MC_VERSION=$(pick_version "PaperMC" "${VERS[@]}")
else
  mapfile -t VERS < <(vanilla_versions)
  MC_VERSION=$(pick_version "Vanilla" "${VERS[@]}")
fi

# --- Login mode -------------------------------------------------------------
if ui_yesno "Player login: require premium (online mode)?

YES (recommended): players must own Minecraft and log in with a Microsoft account. Their skins work and nobody can join under someone else's name.

NO (offline / cracked mode): anyone can join with any username, no account check. Only do this for LAN or trusted friends, and turn on the whitelist." yes
then ONLINE=true; else ONLINE=false; fi

WHITELIST=false
if ui_yesno "Turn on the whitelist? Only players you add with 'whitelist add <name>' can join." \
  "$([[ $ONLINE == false ]] && echo yes || echo no)"; then WHITELIST=true; fi

# --- RAM / port ---------------------------------------------------------------
TOTAL_MB=$(mem_mb)
SUGGEST=$(( TOTAL_MB / 2 )); (( SUGGEST > 8192 )) && SUGGEST=8192; (( SUGGEST < 1024 )) && SUGGEST=1024
SUGGEST=$(( SUGGEST / 1024 * 1024 ))
RAM_CHOICE=$(ui_menu "How much RAM for the Minecraft server? (this computer has ${TOTAL_MB} MB)" "$SUGGEST" \
  "1024" "1 GB  - tiny, 1-3 players" \
  "2048" "2 GB  - small group" \
  "4096" "4 GB  - recommended for most" \
  "6144" "6 GB  - many players / big world" \
  "8192" "8 GB  - large server" \
  "custom" "Type an amount in MB")
[[ "$RAM_CHOICE" == "custom" ]] && RAM_CHOICE=$(ui_input "RAM in MB (e.g. 3072):" "$SUGGEST")
[[ "$RAM_CHOICE" =~ ^[0-9]+$ ]] || die "RAM must be a number of MB."
RAM_MB=$RAM_CHOICE
(( RAM_MB > TOTAL_MB - 512 )) && warn "That is close to or more than all your RAM ($TOTAL_MB MB)."

PORT=$(ui_input "Port players connect to (default 25565):" "25565")
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT > 0 && PORT < 65536 )) || die "Invalid port."
BACKEND_PORT=$(( PORT == 25566 ? 25567 : 25566 ))

# --- Game settings ----------------------------------------------------------
MOTD=$(ui_input "Server name / message shown in the server list (MOTD):" "A Minecraft Server")
MOTD="${MOTD//\"/}"
MAX_PLAYERS=$(ui_input "Maximum players:" "20")
[[ "$MAX_PLAYERS" =~ ^[0-9]+$ ]] || MAX_PLAYERS=20
GAMEMODE=$(ui_menu "Default game mode:" "survival" \
  "survival" "Survival" "creative" "Creative" "adventure" "Adventure" "spectator" "Spectator")
DIFFICULTY=$(ui_menu "Difficulty:" "normal" \
  "peaceful" "Peaceful" "easy" "Easy" "normal" "Normal" "hard" "Hard")
SEED=$(ui_input "World seed (leave empty for random):" "")

# --- Network ------------------------------------------------------------------
NET=$(ui_menu "How will friends outside your home connect?" "tunnel" \
  "tunnel"  "Tunnel - easiest, no router changes needed" \
  "portfwd" "Port forwarding - open a port on your router" \
  "lan"     "LAN only - just people on my Wi-Fi/network")

TUNNEL="none"; NGROK_TOKEN=""; DO_UPNP=no; DO_FIREWALL=no
case "$NET" in
  tunnel)
    TUNNEL=$(ui_menu "Which tunnel provider?" "playit" \
      "playit" "playit.gg - free, made for games, no card (recommended)" \
      "ngrok"  "ngrok - needs a free account; TCP needs card verification" \
      "none"   "I'll set up a tunnel myself (e.g. Cloudflare, Tailscale)")
    if [[ "$TUNNEL" == "ngrok" ]]; then
      NGROK_TOKEN=$(ui_input "Paste your ngrok authtoken (from https://dashboard.ngrok.com/get-started/your-authtoken).
Leave empty to add it later." "" password)
    fi ;;
  portfwd)
    ui_yesno "Try to open the port on your router automatically with UPnP?

Works on many home routers. If it fails you will get manual instructions." yes && DO_UPNP=yes
    ui_yesno "Open port $PORT in this computer's firewall (ufw/firewalld) if one is active?" yes && DO_FIREWALL=yes ;;
  lan)
    ui_yesno "Open port $PORT in this computer's firewall (ufw/firewalld) if one is active?" yes && DO_FIREWALL=yes ;;
esac

# --- Autostart ----------------------------------------------------------------
AUTOSTART=no
if (( IS_MAC )); then
  ui_yesno "Start the server automatically when you log in to this Mac? (installs a small login item)" no && AUTOSTART=yes
elif command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  ui_yesno "Start the server automatically when this computer boots? (installs a systemd service, needs sudo)" no && AUTOSTART=yes
fi

# --- Customisation ------------------------------------------------------------
if ui_yesno "Customise more?

Coloured MOTD, server icon, mods or plugins, whitelist and operators, world type, PvP, command blocks, resource pack, view distance, auto-restart, backups and more.

Choose No to keep sensible defaults." yes; then customise_menu; fi
fi   # end of advanced questions

# --- EULA -----------------------------------------------------------------------
ui_yesno "Minecraft EULA

To run a server you must agree to the Minecraft End User License Agreement:
https://aka.ms/MinecraftEULA

Do you agree to the EULA?" no || { die "You must accept the EULA to run a Minecraft server."; }

# --- Summary --------------------------------------------------------------------
NET_DESC="$NET"; [[ "$NET" == "tunnel" ]] && NET_DESC="tunnel ($TUNNEL)"
[[ "$NET" == "portfwd" ]] && NET_DESC="port forwarding (UPnP: $DO_UPNP)"
SUMMARY="Please check your choices:

  Folder:        $INSTALL_DIR
  Software:      $SOFTWARE $MC_VERSION
  Setup:         $SETUP$([[ $SETUP == velocity ]] && echo " (proxy :$PORT -> backend 127.0.0.1:$BACKEND_PORT)" || true)
  Premium login: $ONLINE   Whitelist: $WHITELIST
  RAM:           ${RAM_MB} MB      Port: $PORT
  MOTD:          $MOTD
  Max players:   $MAX_PLAYERS   Mode: $GAMEMODE   Difficulty: $DIFFICULTY
  Network:       $NET_DESC
  Autostart:     $AUTOSTART
  Bedrock:       $BEDROCK$([[ $BEDROCK == true ]] && echo " (Geyser + Floodgate, UDP $BEDROCK_PORT)" || true)
  Server name:   $SERVER_NAME
  Extras:        icon: ${ICON_SRC:-none}   mods/plugins: ${#MOD_ENTRIES[@]}   loader: $LOADER
                 ops: ${#OP_NAMES[@]}   whitelist names: ${#WL_NAMES[@]}   world: $LEVEL_TYPE

Install now?"
if [[ "$MODE" == "simple" ]]; then
  case "$NET" in tunnel) NET_DESC=$(L "over the internet (free tunnel)") ;; portfwd) NET_DESC=$(L "over the internet (router port forwarding)") ;; *) NET_DESC=$(L "home Wi-Fi only") ;; esac
  SUMMARY="
$(L "Name:")  $SERVER_NAME
$(L "Type:")  $([[ $SOFTWARE == paper ]] && L "Standard" || L "Pure Minecraft") (Minecraft $MC_VERSION)
$(L "Friends:")  $NET_DESC
$(L "Accounts:")  $([[ $ONLINE == true ]] && L "everyone needs a Minecraft account" || L "anyone can join with any name")
$([[ $BEDROCK == true ]] && echo "$(L "Bedrock:")  $(L "phones, consoles and Windows 10/11 can join too")" || true)
$(L "Memory:")  $((RAM_MB / 1024)) GB
$(L "Folder:")  ${INSTALL_DIR/#$HOME/\~}

Install now?"
fi
ui_box "Summary" "${SUMMARY%$'\n\n'Install now?}"
ui_yesno "Install now?" yes || cancelled

# ============================================================================
#  INSTALL
# ============================================================================
mkdir -p "$INSTALL_DIR"

step "Step 1 of 4 - Checking Java"
REQ_JAVA=$(java_for_mc "$MC_VERSION")
info "Minecraft $MC_VERSION needs Java $REQ_JAVA+"
JAVA_BIN=$(ensure_java "$REQ_JAVA")

if [[ "$SETUP" == "velocity" ]]; then SRV_DIR="$INSTALL_DIR/backend"; SRV_WIN=backend; else SRV_DIR="$INSTALL_DIR/server"; SRV_WIN=server; fi
mkdir -p "$SRV_DIR"
step "Step 2 of 4 - Downloading Minecraft (this can take a minute)"
LAUNCH="-jar server.jar --nogui"; MOD_DIR="plugins"

if [[ "$LOADER" != "none" ]]; then
  install_loader "$SRV_DIR"; MOD_DIR="mods"
  JVM_FLAGS="-XX:+UseG1GC"; XMS=$(( RAM_MB / 2 ))
elif [[ "$SOFTWARE" == "paper" ]]; then
  download_papermc paper "$MC_VERSION" "$SRV_DIR/server.jar"
  JVM_FLAGS="$AIKAR_FLAGS -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"
  XMS=$(( RAM_MB >= 2048 ? RAM_MB : RAM_MB / 2 ))
else
  download_vanilla "$MC_VERSION" "$SRV_DIR/server.jar"
  JVM_FLAGS="-XX:+UseG1GC"; XMS=$(( RAM_MB / 2 ))
fi

if [[ -n "$RES_PACK_URL" ]]; then
  info "Calculating the resource pack checksum ..."
  tmp=$(mktemp "$STATE_DIR/pack.XXXXXX")
  if curl -fsSL -A "$UA" -o "$tmp" "$RES_PACK_URL"; then RES_PACK_SHA1=$(hash_file sha1 "$tmp")
  else warn "Could not download the resource pack - skipping it."; RES_PACK_URL=""; fi
  rm -f "$tmp"
fi

if [[ "$SETUP" == "velocity" ]]; then
  # Backend: offline, localhost only - Velocity does the authentication
  write_server_properties "$SRV_DIR" "127.0.0.1" "$BACKEND_PORT" "false"
  write_start_script "$SRV_DIR" "$JAVA_BIN" "$RAM_MB" "$XMS" "$JVM_FLAGS" "$LAUNCH"

  PROXY_DIR="$INSTALL_DIR/proxy"; mkdir -p "$PROXY_DIR"
  VEL_VER=$(velocity_latest); [[ -n "$VEL_VER" && "$VEL_VER" != "null" ]] || die "Could not find a Velocity version."
  PROXY_JAVA=$(ensure_java "$(( REQ_JAVA > 21 ? REQ_JAVA : 21 ))")
  download_papermc velocity "$VEL_VER" "$PROXY_DIR/velocity.jar"
  configure_velocity_toml "$PROXY_DIR" "$PROXY_JAVA"
  configure_paper_for_velocity "$SRV_DIR" "$(tr -d '\n' <"$PROXY_DIR/forwarding.secret")"
  write_start_script "$PROXY_DIR" "$PROXY_JAVA" 512 512 \
    "-XX:+UseG1GC -XX:G1HeapRegionSize=4M -XX:+UnlockExperimentalVMOptions -XX:+ParallelRefProcEnabled -XX:+AlwaysPreTouch -XX:MaxInlineLevel=15" "-jar velocity.jar"
  ICON_DIR="$PROXY_DIR"
else
  write_server_properties "$SRV_DIR" "" "$PORT" "$ONLINE"
  write_start_script "$SRV_DIR" "$JAVA_BIN" "$RAM_MB" "$XMS" "$JVM_FLAGS" "$LAUNCH"
  ICON_DIR="$SRV_DIR"
fi
ok "Server files written to ${SRV_DIR/#$HOME/\~}"

if [[ -n "$ICON_SRC" ]]; then
  if convert_icon "$ICON_SRC" "$ICON_DIR/server-icon.png"; then :; fi
fi
if (( ${#MOD_ENTRIES[@]} )); then
  mkdir -p "$SRV_DIR/$MOD_DIR"
  for e in "${MOD_ENTRIES[@]}"; do
    IFS='|' read -r m_url m_name m_sha <<<"$e"
    m_name="${m_name##*/}"
    download "$m_url" "$SRV_DIR/$MOD_DIR/$m_name"
    verify_hash "$SRV_DIR/$MOD_DIR/$m_name" sha1 "$m_sha"
  done
  ok "${#MOD_ENTRIES[@]} file(s) placed in $SRV_DIR/$MOD_DIR"
fi
if [[ "$BEDROCK" == true ]]; then install_geyser "$SRV_DIR"; fi
if (( ${#WL_NAMES[@]} + ${#OP_NAMES[@]} )); then write_player_lists "$SRV_DIR"; fi
if [[ "$BACKUP_SCRIPT" == "true" ]]; then write_backup_script "$SRV_WIN"; fi

step "Step 3 of 4 - Setting up internet access"
# --- Networking -----------------------------------------------------------------
case "$TUNNEL" in
  playit) install_playit ;;
  ngrok)  install_ngrok ;;
esac
[[ "$DO_FIREWALL" == "yes" ]] && open_firewall "$PORT"
[[ "$DO_FIREWALL" == "yes" && "$BEDROCK" == true ]] && open_firewall "$BEDROCK_PORT" udp
UPNP_OK=no
rm -f "$INSTALL_DIR/upnp-refresh.sh"
[[ "$DO_UPNP" == "yes" ]] && try_upnp "$PORT" && UPNP_OK=yes
if [[ "$DO_UPNP" == "yes" && "$BEDROCK" == true ]]; then try_upnp "$BEDROCK_PORT" UDP || UPNP_OK=no; fi

if (( ! IS_MAC )) && ! command -v tmux >/dev/null 2>&1 && ! command -v screen >/dev/null 2>&1; then
  pkg_install tmux || warn "tmux is not installed, so the server will run in the background (logs are in the logs folder). To get tmux: $(pkg_hint tmux)"
fi
write_launchers
if [[ "$TUNNEL" == "playit" ]]; then
  step "playit.gg tunnel"
  if ui_yesno "Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)" yes; then tunnel_guide; fi
fi
step "Step 4 of 4 - Finishing up"
if [[ "$AUTOSTART" == "yes" ]]; then if (( IS_MAC )); then install_launchd; else install_systemd; fi; fi

# Remember the answers
cat >"$INSTALL_DIR/mc-setup.conf" <<EOF
# Answers used by mc-setup.sh v$SCRIPT_VERSION on $(date)
SERVER_NAME=$SERVER_NAME
SOFTWARE=$SOFTWARE
LOADER=$LOADER
MC_VERSION=$MC_VERSION
SETUP=$SETUP
ONLINE=$ONLINE
RAM_MB=$RAM_MB
PORT=$PORT
NET=$NET
TUNNEL=$TUNNEL
PUBLIC_ADDRESS=$PUBLIC_ADDR
BEDROCK=$BEDROCK
BEDROCK_PORT=$BEDROCK_PORT
PUBLIC_ADDRESS_BEDROCK=$PUBLIC_ADDR_BE
JAVA_BIN=$JAVA_BIN
EOF

# --- Final instructions ---------------------------------------------------------
LAN=$(lan_ip); [[ -z "$LAN" ]] && LAN="<this-pc-ip>"
NEXT="Done! Your server is in:
  $INSTALL_DIR

Start everything:   $INSTALL_DIR/start-all.sh --attach
Stop everything:    $INSTALL_DIR/stop-all.sh
On the same network, connect to:  $LAN:$PORT
"
case "$NET:$TUNNEL" in
  tunnel:playit) NEXT+="
playit.gg tunnel:
$([[ -n "$PUBLIC_ADDR" ]] && echo "  Friends connect to:  $PUBLIC_ADDR" || echo "  Not finished yet - run   bash mc-setup.sh --tunnel-guide   for the step-by-step guide.")
  Make sure playit is running (and the tunnel points to 127.0.0.1:$PORT) before friends join.
" ;;
  tunnel:ngrok) NEXT+="
ngrok tunnel:
  Friends connect to the address ngrok shows after 'tcp://' (e.g. 0.tcp.eu.ngrok.io:12345).
  $([[ -z "$NGROK_TOKEN" ]] && echo "Add your token first: $INSTALL_DIR/tools/ngrok config add-authtoken <TOKEN> --config $INSTALL_DIR/tools/ngrok.yml" || true)
" ;;
  tunnel:none) NEXT+="
Point your own tunnel at TCP 127.0.0.1:$PORT.
" ;;
  portfwd:*)
    PUB=$(public_ip)
    if [[ "$UPNP_OK" == "yes" ]]; then NEXT+="
Port forwarding via UPnP is active. Friends connect to:  $PUB:$PORT
(If it stops working after a router reboot run upnp-refresh.sh)
"
    else NEXT+="
Port forwarding - do this on your router's admin page (often http://192.168.0.1 or 192.168.1.1):
  Forward TCP port $PORT  ->  $LAN  port $PORT
  Tip: give this PC a fixed/reserved IP in the router's DHCP settings.
Friends then connect to:  $PUB:$PORT
Note: this does not work if your ISP uses CGNAT - use a tunnel instead.
"
    fi ;;
esac
if [[ "$BEDROCK" == true ]]; then
  case "$NET:$TUNNEL" in
    tunnel:playit) NEXT+="
Bedrock players (UDP $BEDROCK_PORT):  $([[ -n "$PUBLIC_ADDR_BE" ]] && echo "$PUBLIC_ADDR_BE   (address and port in the two Bedrock boxes)" || echo "not set up yet - run   bash mc-setup.sh --tunnel-guide")" ;;
    portfwd:*) NEXT+="
Bedrock players:  $PUB:$BEDROCK_PORT   (forward UDP $BEDROCK_PORT on your router too$([[ "$UPNP_OK" == "yes" ]] && echo ", done by UPnP" || true))" ;;
    *) NEXT+="
Bedrock players on the same network:  $LAN  port $BEDROCK_PORT" ;;
  esac
  NEXT+="
Bedrock player names get a dot in front (for example .Steve) because of Floodgate."
fi
[[ "$ONLINE" == "false" ]] && NEXT+="
Offline mode is ON: anyone can join with any name. Keep the whitelist on!"
NEXT+="
Make yourself admin: in the server console type   op <YourName>"

if [[ "$MODE" == "simple" ]]; then
  case "$NET:$TUNNEL" in
    tunnel:playit)
      if [[ -n "$PUBLIC_ADDR" ]]; then JOIN=">> $PUBLIC_ADDR

(Your playit.gg address. Keep playit running while you play.)"
      else JOIN=">> (not set up yet)

Run  bash mc-setup.sh --tunnel-guide  for the step-by-step guide to get your address."; fi ;;
    portfwd:*)
      PUB=$(public_ip)
      if [[ "$UPNP_OK" == "yes" ]]; then JOIN=">> $PUB:$PORT"
      else JOIN=">> $PUB:$PORT

First open port $PORT on your router and send it to $LAN (see the README)."; fi ;;
    *) JOIN=">> $LAN:$PORT

(Only on the same Wi-Fi.)" ;;
  esac
  NEXT="To start your server, run:
>> ${INSTALL_DIR/#$HOME/\~}/start-all.sh --attach

To stop it, type  stop  in the server window.

Friends join with:
$JOIN"
  if [[ "$BEDROCK" == true ]]; then
    case "$NET:$TUNNEL" in
      tunnel:playit) BEDROCK_JOIN="$([[ -n "$PUBLIC_ADDR_BE" ]] && echo ">> $PUBLIC_ADDR_BE" || echo ">> (not set up yet)")" ;;
      portfwd:*) BEDROCK_JOIN=">> $PUB:$BEDROCK_PORT" ;;
      *) BEDROCK_JOIN=">> $LAN:$BEDROCK_PORT" ;;
    esac
    NEXT+="

$(L "Bedrock players (phones, consoles, Windows 10/11) join with:")
$BEDROCK_JOIN
$(L "(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)")"
  fi
  [[ "$ONLINE" == "false" ]] && NEXT+="

Note: anyone can join with any name. Only share the address with people you trust."
fi
bar_line
ui_box "Your server is ready" "$NEXT"

if [[ -t 0 ]] && ui_yesno "Start the server now?" yes; then
  printf '%s%s%s  Starting...\n' "$C_GREEN" "$S_END" "$C_RESET" >&2
  exec "$INSTALL_DIR/start-all.sh" --attach
fi
printf '%s%s%s  %s\n' "$C_GREEN" "$S_END" "$C_RESET" "$(L "All set - have fun!")" >&2
