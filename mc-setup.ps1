<#
  mc-setup.ps1 - Interactive Minecraft (Java Edition) server installer for Windows

  Asks you a few questions in the console, then:
    * downloads Vanilla (Mojang) or PaperMC from the official APIs
    * optionally puts a Velocity proxy in front of it (modern forwarding)
    * sets "online mode" (premium Microsoft account login) on or off
    * makes sure a suitable Java is available (downloads Temurin if needed)
    * sets up a tunnel (playit.gg / ngrok) or helps with port forwarding (UPnP)
    * writes server.properties, eula.txt and double-clickable start scripts

  Easiest: double-click mc-setup.bat (it runs this file).
  Or in PowerShell:  powershell -ExecutionPolicy Bypass -File .\mc-setup.ps1
  Works with Windows PowerShell 5.1 (built into Windows 10/11) and PowerShell 7.
#>
param([switch]$TunnelGuide, [switch]$Customize, [string]$Server = '', [string]$Lang = '')
$ErrorActionPreference = 'Stop'
if ($Lang) { $env:MCS_LANG = $Lang }
$ProgressPreference    = 'SilentlyContinue'   # makes Invoke-WebRequest much faster
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$ScriptVersion  = '1.1.0'
$MojangManifest = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
$PaperApi       = 'https://fill.papermc.io/v3/projects'
$AdoptiumApi    = 'https://api.adoptium.net/v3/binary/latest'
$PlayitBase     = 'https://github.com/playit-cloud/playit-agent/releases/latest/download'
$NgrokBase      = 'https://bin.equinox.io/c/bNyj1mQVY4c'
$UA             = "mc-setup.ps1/$ScriptVersion"

# ---------------------------------------------------------------------------
#  POPULAR PLUGINS & MODS - the pick-list is built from these tables.
#  To add one, add a line:  'modrinth-slug|Name shown|Short description'
#  (the slug is the end of its Modrinth link: modrinth.com/plugin/<slug>).
#  You can also add lines without editing this script: put them in a file called
#  plugins.list (Paper plugins) or mods.list (Fabric/Forge/NeoForge mods) next to
#  this script. '#' starts a comment. Only entries that work with your chosen
#  Minecraft version and server type are shown.
# ---------------------------------------------------------------------------
$PluginCatalog = @(
  'essentialsx|EssentialsX|Homes, warps, kits and ~100 everyday commands'
  'luckperms|LuckPerms|Ranks and permissions'
  'worldedit|WorldEdit|Build tool: copy, paste and edit big areas'
  'fastasyncworldedit|FastAsyncWorldEdit|Faster WorldEdit for huge edits (use instead of WorldEdit)'
  'worldguard|WorldGuard|Protect regions from griefing'
  'coreprotect|CoreProtect|Log everything and roll back griefing'
  'griefprevention|GriefPrevention|Players claim land with a golden shovel'
  'vaultunlocked|VaultUnlocked|Economy and permissions bridge (the maintained Vault)'
  'placeholderapi|PlaceholderAPI|Placeholders many other plugins use'
  'chunky|Chunky|Pre-generate the world so exploring doesn''t lag'
  'chunkyborder|Chunky Border|Nice world border'
  'geyser|Geyser|Let Bedrock players (phone, console) join'
  'floodgate|Floodgate|Bedrock players join without a Java account'
  'viaversion|ViaVersion|Newer Minecraft versions can join'
  'viabackwards|ViaBackwards|Older Minecraft versions can join'
  'viarewind|ViaRewind|Very old clients (1.8) can join'
  'simple-voice-chat|Simple Voice Chat|Talk to nearby players (proximity voice)'
  'dynmap|Dynmap|Live map of your world in a web browser'
  'bluemap|BlueMap|Pretty 3D web map'
  'skinsrestorer|SkinsRestorer|Show real skins on offline-mode servers'
  'tab-was-taken|TAB|Custom player list, name tags and scoreboards'
  'decentholograms|DecentHolograms|Floating text holograms'
  'huskhomes|HuskHomes|Homes, warps and teleport requests'
  'multiverse-core|Multiverse-Core|Run several worlds on one server'
  'grimac|Grim Anticheat|Stops common cheats'
  'libertybans|LibertyBans|Bans, mutes and warnings'
  'quickshop-hikari|QuickShop-Hikari|Player chest shops'
  'chestshop|ChestShop|Sign-based shops'
  'betterstructures|BetterStructures|More structures to find in the world'
)
$ModCatalog = @(
  'lithium|Lithium|Big server speed-up, no gameplay changes'
  'ferrite-core|FerriteCore|Uses much less memory'
  'c2me-fabric|C2ME|Faster chunk loading and generation'
  'krypton|Krypton|Faster networking'
  'vmp-fabric|Very Many Players|Helps servers with lots of players'
  'no-chat-reports|No Chat Reports|Turns off chat reporting / signing'
  'spark|spark|Performance profiler (find what causes lag)'
  'simple-voice-chat|Simple Voice Chat|Talk to nearby players (proximity voice)'
  'luckperms|LuckPerms|Ranks and permissions'
  'worldedit|WorldEdit|Build tool: copy, paste and edit big areas'
  'chunky|Chunky|Pre-generate the world so exploring doesn''t lag'
  'bluemap|BlueMap|Pretty 3D web map'
  'dynmap|Dynmap|Live map of your world in a web browser'
  'essential-commands|Essential Commands|Home, warp and teleport commands'
  'ledger|Ledger|Log and roll back griefing'
  'universal-graves|Universal Graves|Keep your stuff in a grave when you die'
  'styled-chat|Styled Chat|Coloured and formatted chat'
  'carpet|Carpet|Technical / redstone tweaks'
  'lootr|Lootr|Every player gets their own loot in chests'
)

# ---------------------------------------------------------------------------
#  LANGUAGES. Text is looked up by its English wording; anything missing falls
#  back to English. To add a language: make a file  lang\<code>.txt  next to this
#  script with lines  English text<TAB>translation  (see the blocks below), then
#  run with  -Lang <code>  (or pick it from the list).
# ---------------------------------------------------------------------------
$script:TR = @{}; $script:BoxOpen = $false
$LangData = @{}
$LangData['es'] = @'
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
'@
$LangData['fr'] = @'
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
'@
$LangData['de'] = @'
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
'@
$LangData['pt'] = @'
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
'@
$LangData['ru'] = @'
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
'@
$LangData['zh'] = @'
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
'@
$LangData['ja'] = @'
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
'@
$LangData['ko'] = @'
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
'@
$LangData['hi'] = @'
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
'@
$LangData['ar'] = @'
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
'@
$LangData['he'] = @'
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
'@
$LangData['tr'] = @'
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
'@
$LangData['it'] = @'
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
'@

function Load-Lang([string]$code) {
  $script:TR = @{}; $script:BoxOpen = $false
  if ($code -eq 'en') { return }
  $texts = @()
  if ($LangData.ContainsKey($code)) { $texts += $LangData[$code] }
  foreach ($d in @($PSScriptRoot, (Get-Location).Path)) {
    if (-not $d) { continue }
    $f = Join-Path $d "lang\$code.txt"
    if (Test-Path $f) { $texts += [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) }
  }
  foreach ($blk in $texts) {
    foreach ($l in ($blk -split "`r?`n")) {
      $p = $l.Split("`t", 2)
      if ($p.Count -eq 2 -and $p[0] -and $p[1] -and -not $p[0].StartsWith('#')) { $script:TR[$p[0]] = $p[1] }
    }
  }
  if ('zh', 'ja', 'ko', 'hi', 'ar', 'he' -contains $code) { $script:BoxOpen = $true }
}
function L([string]$t, [switch]$NoWrap) {   # translate a (possibly multi-line) message line by line; unknown lines stay English
  if ($script:TR.Count -eq 0 -or -not $t) { return $t }
  $out = @()
  foreach ($line in ($t -split "`r?`n")) {
    if ($line -and $script:TR.ContainsKey($line)) {
      $line = $script:TR[$line]
    }
    $out += $line
  }
  return ($out -join "`n")
}
function Lf {   # translated template with {0} {1} filled in
  param([string]$t)
  $a = @($args)
  $r = L $t
  for ($i = 0; $i -lt $a.Count; $i++) { $r = $r.Replace("{$i}", "$($a[$i])") }
  return $r
}
function Lang-FromLocale {
  $l = $env:MCS_LANG
  if (-not $l) { try { $l = (Get-Culture).TwoLetterISOLanguageName } catch { $l = 'en' } }
  $l = "$l".ToLower() -replace '[-_.@].*', ''
  if ($l -eq 'iw') { $l = 'he' }
  if ('en', 'es', 'fr', 'de', 'pt', 'ru', 'zh', 'ja', 'ko', 'hi', 'ar', 'he', 'tr', 'it' -contains $l) { return $l }
  return 'en'
}
function Pick-Language {
  if ($env:MCS_LANG) { $code = Lang-FromLocale }
  else {
    $code = Ask-Menu 'Language / 语言 / भाषा / اللغة / שפה' @(
      @('en', 'English'), @('zh', '中文'), @('hi', 'हिन्दी'), @('ar', 'العربية'), @('he', 'עברית'), @('es', 'Español'), @('fr', 'Français'),
      @('de', 'Deutsch'), @('pt', 'Português'), @('ru', 'Русский'), @('ja', '日本語'), @('ko', '한국어'), @('tr', 'Türkçe'), @('it', 'Italiano')) (Lang-FromLocale)
  }
  Load-Lang $code   # so the warning below is already in the chosen language
  if ('zh', 'ja', 'ko', 'hi', 'ar', 'he', 'ru' -contains $code) {
    $weak = ($env:OS -eq 'Windows_NT' -and -not $env:WT_SESSION -and -not $env:MCS_FORCE_LANG)
    if ($weak -and ('zh', 'ja', 'ko', 'hi', 'ar', 'he' -contains $code)) {
      $c = Ask-Menu 'Not sure this window can show this language. If you see squares or ? after choosing it, restart and pick English (Windows Terminal from the Microsoft Store works best).' @(@('try', 'Use this language'), @('en', 'Use English instead')) 'try'
      if ($c -eq 'en') { $code = 'en'; Load-Lang 'en' }
    } elseif ('zh', 'ja', 'ko', 'hi', 'ar', 'he' -contains $code) {
      Info 'Tip: if you see squares instead of letters, run again with  -Lang en  or use Windows Terminal.'
    }
  }
}

# ---------------------------------------------------------------------------
#  Look & feel: UTF-8, ANSI colours, symbols, banner (falls back gracefully)
# ---------------------------------------------------------------------------
$script:Esc = [char]27; $ESC = $script:Esc
$script:Fancy = $false      # arrow-key menus need a real console
try { $script:Fancy = (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected) -and ($env:MCS_UI -ne 'text') } catch {}
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); $OutputEncoding = [Console]::OutputEncoding } catch {}
$script:Color = $false
if ($env:OS -eq 'Windows_NT') {
  # switch on ANSI escape codes in the classic console (Windows Terminal already has them)
  try {
    Add-Type -Namespace McSetup -Name Vt -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out int m); [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, int m);'
    $vtH = [McSetup.Vt]::GetStdHandle(-11); $vtM = 0
    if ([McSetup.Vt]::GetConsoleMode($vtH, [ref]$vtM)) { $script:Color = [McSetup.Vt]::SetConsoleMode($vtH, ($vtM -bor 4)) }
  } catch {}
} else { try { $script:Color = -not [Console]::IsOutputRedirected } catch {} }
if ($env:NO_COLOR) { $script:Color = $false }
if (-not $script:Color) { $script:Fancy = $false }      # cursor movement needs ANSI


if ($script:Color) {
  $cR = "$ESC[0m"; $cB = "$ESC[1m"; $cD = "$ESC[2m"; $cRed = "$ESC[31m"; $cY = "$ESC[33m"; $cC = "$ESC[36m"; $cG = "$ESC[32m"
  $cA = "$ESC[38;5;77m"; $cGr = "$ESC[38;5;243m"
} else { $cR = ''; $cB = ''; $cD = ''; $cRed = ''; $cY = ''; $cC = ''; $cG = ''; $cA = ''; $cGr = '' }
if ($env:MCS_ASCII) {
  $Sym = @{ top = '+'; bar = '|'; end = '+'; act = '*'; done = 'o'; on = '(*)'; off = '( )'; ok = 'v'; warn = '!'; err = 'x'; info = '-'; boxon = '[x]'; boxoff = '[ ]'; tr = '+'; bl = '+'; br = '+'; h = '-'; full = '#'; empty = '.' }
  $script:Spin = @('|', '/', '-', '\'); $script:Utf = $false
} else {
  $Sym = @{ top = [string][char]0x250C; bar = [string][char]0x2502; end = [string][char]0x2514; act = [string][char]0x25C6; done = [string][char]0x25C7
          on = [string][char]0x25CF; off = [string][char]0x25CB; ok = [string][char]0x2714; warn = [string][char]0x25B2; err = [string][char]0x25A0; info = [string][char]0x2022
          boxon = [string][char]0x25FC; boxoff = [string][char]0x25FB; tr = [string][char]0x256E; bl = [string][char]0x251C; br = [string][char]0x256F; h = [string][char]0x2500
          full = [string][char]0x2588; empty = [string][char]0x2591 }
  $script:Spin = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F | ForEach-Object { [string][char]$_ }); $script:Utf = $true
}

# ---------------------------------------------------------------------------
#  Right-to-left text (Hebrew / Arabic). Consoles such as Windows Terminal print characters left to right and
#  do not reorder them, so every line that contains Hebrew/Arabic is converted ONCE, in Out-Raw, to display order:
#  words and letters reversed, English words / numbers / paths kept readable, brackets mirrored, Arabic letters joined.
#  All the program's text is kept in normal (logical) order until then. MCS_BIDI=1 turns the conversion off for a
#  terminal that reorders by itself; MCS_BIDI=0 forces it on.
# ---------------------------------------------------------------------------
$script:Vis = $false
if ($env:OS -eq 'Windows_NT') { $script:Vis = ($env:MCS_BIDI -ne '1') } else { $script:Vis = ($env:MCS_BIDI -eq '0') }
$script:RtlRe = '[\u0590-\u06FF\u0750-\u077F\uFB1D-\uFDFF\uFE70-\uFEFF]'
$script:ArForm = @{}; $script:ArLig = @{}
foreach ($e in ('0621:FE80:0:0:0 0622:FE81:FE82:0:0 0623:FE83:FE84:0:0 0624:FE85:FE86:0:0 0625:FE87:FE88:0:0 0626:FE89:FE8A:FE8B:FE8C 0627:FE8D:FE8E:0:0 0628:FE8F:FE90:FE91:FE92 0629:FE93:FE94:0:0 062A:FE95:FE96:FE97:FE98 062B:FE99:FE9A:FE9B:FE9C 062C:FE9D:FE9E:FE9F:FEA0 062D:FEA1:FEA2:FEA3:FEA4 062E:FEA5:FEA6:FEA7:FEA8 062F:FEA9:FEAA:0:0 0630:FEAB:FEAC:0:0 0631:FEAD:FEAE:0:0 0632:FEAF:FEB0:0:0 0633:FEB1:FEB2:FEB3:FEB4 0634:FEB5:FEB6:FEB7:FEB8 0635:FEB9:FEBA:FEBB:FEBC 0636:FEBD:FEBE:FEBF:FEC0 0637:FEC1:FEC2:FEC3:FEC4 0638:FEC5:FEC6:FEC7:FEC8 0639:FEC9:FECA:FECB:FECC 063A:FECD:FECE:FECF:FED0 0641:FED1:FED2:FED3:FED4 0642:FED5:FED6:FED7:FED8 0643:FED9:FEDA:FEDB:FEDC 0644:FEDD:FEDE:FEDF:FEE0 0645:FEE1:FEE2:FEE3:FEE4 0646:FEE5:FEE6:FEE7:FEE8 0647:FEE9:FEEA:FEEB:FEEC 0648:FEED:FEEE:0:0 0649:FEEF:FEF0:0:0 064A:FEF1:FEF2:FEF3:FEF4' -split ' ')) {
  $p = $e -split ':'
  $script:ArForm[[Convert]::ToInt32($p[0], 16)] = @(1..4 | ForEach-Object { if ($p[$_] -eq '0') { $null } else { [string][char][Convert]::ToInt32($p[$_], 16) } })
}
foreach ($e in ('0622:FEF5:FEF6 0623:FEF7:FEF8 0625:FEF9:FEFA 0627:FEFB:FEFC' -split ' ')) {
  $p = $e -split ':'
  $script:ArLig[[Convert]::ToInt32($p[0], 16)] = @([string][char][Convert]::ToInt32($p[1], 16), [string][char][Convert]::ToInt32($p[2], 16))
}
function Bidi-IsR([int]$c) {
  if ($c -ge 0x590 -and $c -le 0x5FF) { return $true }
  if ($c -ge 0x600 -and $c -le 0x6FF) {
    if ($c -eq 0x60C -or $c -eq 0x670 -or ($c -ge 0x660 -and $c -le 0x669) -or ($c -ge 0x610 -and $c -le 0x61A) -or ($c -ge 0x64B -and $c -le 0x65F) -or ($c -ge 0x6D6 -and $c -le 0x6ED)) { return $false }
    return $true
  }
  return (($c -ge 0x750 -and $c -le 0x77F) -or ($c -ge 0xFB1D -and $c -le 0xFDFF) -or ($c -ge 0xFE70 -and $c -le 0xFEFF))
}
function Bidi-IsMark([int]$c) {
  return (($c -ge 0x591 -and $c -le 0x5BD) -or $c -eq 0x5BF -or $c -eq 0x5C1 -or $c -eq 0x5C2 -or $c -eq 0x5C4 -or $c -eq 0x5C5 -or $c -eq 0x5C7 -or ($c -ge 0x64B -and $c -le 0x65F) -or $c -eq 0x670 -or ($c -ge 0x610 -and $c -le 0x61A))
}
function Bidi-Join([int]$c) {   # D = joins both sides, R = joins the letter before it only, U = does not join
  $f = $script:ArForm[$c]
  if (-not $f) { return 'U' }
  if ($f[2]) { return 'D' }
  if ($f[1]) { return 'R' }
  return 'U'
}
# $cells: letters (a letter plus its marks = one cell) in logical order -> @{ t = display cells in LOGICAL order, i = index of the source cell }
function Bidi-Shape($cells) {
  $n = $cells.Count; $t = @(); $ix = @(); $skip = -1
  for ($i = 0; $i -lt $n; $i++) {
    if ($i -eq $skip) { continue }
    $c = [int][char]$cells[$i][0]; $rest = $cells[$i].Substring(1)
    if ((Bidi-Join $c) -eq 'U') { $t += $cells[$i]; $ix += $i; continue }
    $j = $i - 1; while ($j -ge 0 -and (Bidi-IsMark ([int][char]$cells[$j][0]))) { $j-- }
    $pj = ($j -ge 0 -and (Bidi-Join ([int][char]$cells[$j][0])) -eq 'D' -and (Bidi-IsR ([int][char]$cells[$j][0])))
    if ($c -eq 0x644 -and $i + 1 -lt $n -and $script:ArLig.ContainsKey([int][char]$cells[$i + 1][0])) {
      $lg = $script:ArLig[[int][char]$cells[$i + 1][0]]
      $f = $lg[0]; if ($pj) { $f = $lg[1] }
      $t += ($f + $rest + $cells[$i + 1].Substring(1)); $ix += $i; $skip = $i + 1; continue
    }
    $nj = $false
    if ((Bidi-Join $c) -eq 'D') {
      $j = $i + 1; while ($j -lt $n -and (Bidi-IsMark ([int][char]$cells[$j][0]))) { $j++ }
      if ($j -lt $n -and (Bidi-Join ([int][char]$cells[$j][0])) -ne 'U') { $nj = $true }
    }
    $f = $script:ArForm[$c]   # iso, final, initial, medial
    $g = $f[0]
    if ($pj -and $nj -and $f[3]) { $g = $f[3] } elseif ($pj -and $f[1]) { $g = $f[1] } elseif ($nj -and $f[2]) { $g = $f[2] }
    $t += ($g + $rest); $ix += $i
  }
  return @{ t = $t; i = $ix }
}
# $cells: letters in logical order -> @{ t = cells in display order; i = source index of each }
function Bidi-Core($cells) {
  $n = $cells.Count
  $k = New-Object 'char[]' $n; $base = ''
  for ($j = 0; $j -lt $n; $j++) {
    $c = [int][char]$cells[$j][0]
    if (Bidi-IsR $c) { $k[$j] = 'R' }
    elseif ([char]::IsLetterOrDigit([char]$c) -or ($c -ge 0x2E80 -and -not ($c -ge 0x3000 -and $c -le 0x3003))) { $k[$j] = 'L' }
    else { $k[$j] = 'N' }
    if ($base -eq '' -and $k[$j] -ne 'N') { $base = [string]$k[$j] }
  }
  if ($base -eq '') { return @{ t = @($cells); i = @(0..($n - 1)) } }
  for ($j = 0; $j -lt $n; $j++) {   # % $ etc. stick to a neighbouring number
    if ($k[$j] -eq 'N' -and $cells[$j].Length -eq 1 -and '%$€£¢°#'.Contains($cells[$j])) {
      if (($j -gt 0 -and [char]::IsDigit($cells[$j - 1][0])) -or ($j + 1 -lt $n -and [char]::IsDigit($cells[$j + 1][0]))) { $k[$j] = 'L' }
    }
  }
  for ($j = 0; $j -lt $n; $j++) {   # command-line flags such as -Lang / --lang stay together
    if ($cells[$j] -eq '-' -and $k[$j] -eq 'N' -and ($j -eq 0 -or $cells[$j - 1] -eq ' ' -or $cells[$j - 1] -eq '-') -and $j + 1 -lt $n -and ($cells[$j + 1] -eq '-' -or $cells[$j + 1] -match '^[A-Za-z]')) { $k[$j] = 'L' }
  }
  $i = 0
  while ($i -lt $n) {   # neutrals take the direction of both neighbours when they agree, otherwise the paragraph direction
    if ($k[$i] -ne 'N') { $i++; continue }
    $j = $i; while ($j -lt $n -and $k[$j] -eq 'N') { $j++ }
    $l = $base; if ($i -gt 0) { $l = [string]$k[$i - 1] }
    $r = $base; if ($j -lt $n) { $r = [string]$k[$j] }
    $d = $base; if ($l -eq $r) { $d = $l }
    for ($x = $i; $x -lt $j; $x++) { $k[$x] = $d[0] }
    $i = $j
  }
  $runs = New-Object System.Collections.Generic.List[object]
  $i = 0
  while ($i -lt $n) {
    $j = $i; while ($j -lt $n -and $k[$j] -eq $k[$i]) { $j++ }
    $seg = @(); for ($x = $i; $x -lt $j; $x++) { $seg += , $cells[$x] }
    $ixs = @($i..($j - 1))
    if ($k[$i] -eq 'R') {
      $sh = Bidi-Shape $seg
      $seg = @($sh.t); $ixs = @($sh.i | ForEach-Object { $_ + $i })
      [array]::Reverse($seg); [array]::Reverse($ixs)
      $seg = @($seg | ForEach-Object { switch ($_) { '(' { ')' } ')' { '(' } '[' { ']' } ']' { '[' } '{' { '}' } '}' { '{' } '<' { '>' } '>' { '<' } default { $_ } } })
    }
    $runs.Add(@{ t = $seg; i = $ixs })
    $i = $j
  }
  $ot = @(); $oi = @()
  $order = @(0..($runs.Count - 1)); if ($base -eq 'R') { [array]::Reverse($order) }
  foreach ($r in $order) { $ot += $runs[$r].t; $oi += $runs[$r].i }
  return @{ t = $ot; i = $oi }
}
function Bidi-Visual([string]$s) {   # plain text (no colour codes) -> display order
  if ($s -notmatch $script:RtlRe) { return $s }
  $cells = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($s, '[\uD800-\uDBFF][\uDC00-\uDFFF]|.', 'Singleline')) {
    if ($cells.Count -gt 0 -and (Bidi-IsMark ([int][char]$m.Value[0]))) { $cells[$cells.Count - 1] += $m.Value } else { $cells.Add($m.Value) }
  }
  $tail = 0; while ($cells.Count -gt 0 -and $cells[$cells.Count - 1] -eq ' ') { $cells.RemoveAt($cells.Count - 1); $tail++ }
  $r = Bidi-Core $cells.ToArray()
  return ((@($r.t) -join '') + (' ' * $tail))
}
# One printed line that may contain colour codes: keep the leading symbols (bar, bullet, "1)") on the left, wrap long text,
# convert each piece, keep the colours attached to their letters.
function Vis-Line([string]$line) {
  if ($line -notmatch $script:RtlRe) { return $line }
  $ESCc = [char]27
  $cells = New-Object System.Collections.Generic.List[string]; $sty = New-Object System.Collections.Generic.List[string]
  $pre = ''; $suf = ''; $cur = ''; $seen = $false
  foreach ($m in [regex]::Matches($line, "\x1b\[[0-9;?]*[A-Za-z]|\r|[\uD800-\uDBFF][\uDC00-\uDFFF]|.", 'Singleline')) {
    $v = $m.Value
    if ($v[0] -eq $ESCc) {
      if ($v.EndsWith('m')) { $p = $v.Substring(2, $v.Length - 3); if ($p -eq '' -or $p -eq '0') { $cur = '' } else { $cur += $v } }
      elseif ($seen) { $suf += $v } else { $pre += $v }
    } elseif ($v -eq "`r") { if ($seen) { $suf += $v } else { $pre += $v } }
    elseif ($cells.Count -gt 0 -and (Bidi-IsMark ([int][char]$v[0]))) { $cells[$cells.Count - 1] += $v }
    else { $cells.Add($v); $sty.Add($cur); $seen = $true }
  }
  $n = $cells.Count; $c0 = 0
  $chrome = [string]::Concat([char]0x2502, [char]0x250C, [char]0x2514, [char]0x25C6, [char]0x25C7, [char]0x25CF, [char]0x25CB, [char]0x2714, [char]0x25B2, [char]0x25A0, [char]0x2022, [char]0x25FC, [char]0x25FB, [char]0x256E, [char]0x251C, [char]0x256F, [char]0x2500, ' ')
  while ($c0 -lt $n) {
    $c = $cells[$c0]
    if ($c.Length -eq 1 -and $chrome.Contains($c)) { $c0++; continue }
    if ($c -match '^\d$') { $j = $c0; while ($j -lt $n -and $cells[$j] -match '^\d$') { $j++ }; if ($j -lt $n -and $cells[$j] -eq ')') { $c0 = $j + 1; continue } }
    break
  }
  $end = $n; while ($end -gt $c0 -and $cells[$end - 1] -eq ' ') { $end-- }
  $emit = {
    param($texts, $styles)
    $sb = New-Object System.Text.StringBuilder; $last = ''
    for ($x = 0; $x -lt $texts.Count; $x++) {
      $st = $styles[$x]
      if ($st -ne $last) { if ($last -ne '') { [void]$sb.Append("$ESCc[0m") }; [void]$sb.Append($st); $last = $st }
      [void]$sb.Append($texts[$x])
    }
    if ($last -ne '') { [void]$sb.Append("$ESCc[0m") }
    $sb.ToString()
  }
  $room = (Get-Width) - 2 - $c0
  if ($room -lt 20) { $room = 20 }
  $pieces = New-Object System.Collections.Generic.List[object]   # split the text part into pieces that fit (at spaces)
  $s0 = $c0
  while ($s0 -lt $end) {
    $e0 = [Math]::Min($end, $s0 + $room)
    if ($e0 -lt $end) { $b = $e0; while ($b -gt $s0 + 1 -and $cells[$b - 1] -ne ' ') { $b-- }; if ($b -gt $s0 + 1) { $e0 = $b } }
    $pieces.Add(@($s0, $e0)); $s0 = $e0
    while ($s0 -lt $end -and $cells[$s0] -eq ' ') { $s0++ }
  }
  if ($pieces.Count -eq 0) { return $line }
  $headFirst = ''; $headNext = ''
  if ($c0 -gt 0) {
    $headFirst = & $emit @($cells[0..($c0 - 1)]) @($sty[0..($c0 - 1)])
    $bs = $sty[0]; $br = ''; if ($bs -ne '') { $br = "$ESCc[0m" }
    $headNext = $bs + [string][char]0x2502 + $br + (' ' * ($c0 - 1))
  }
  $out = New-Object System.Collections.Generic.List[string]
  for ($pi = 0; $pi -lt $pieces.Count; $pi++) {
    $pc = $pieces[$pi]
    $seg = @(); $segSty = @()
    $pe = $pc[1]; while ($pe -gt $pc[0] + 1 -and $cells[$pe - 1] -eq ' ') { $pe-- }
    for ($x = $pc[0]; $x -lt $pe; $x++) { $seg += , $cells[$x]; $segSty += , $sty[$x] }
    $r = Bidi-Core $seg
    $vt = @($r.t); $vs = @($r.i | ForEach-Object { $segSty[$_] })
    $head = $headNext; if ($pi -eq 0) { $head = $headFirst }
    $tail = ''; if ($pi -eq $pieces.Count - 1 -and $end -lt $n) { $tail = (' ' * ($n - $end)) }
    $out.Add($head + (& $emit $vt $vs) + $tail)
  }
  return ($pre + ($out -join "`n") + $suf)
}
function Vis-Text([string]$s) {
  $parts = $s.Split([char]10)
  for ($i = 0; $i -lt $parts.Count; $i++) { $parts[$i] = Vis-Line $parts[$i] }
  return ($parts -join "`n")
}
function Out-Raw([string]$s) {   # the ONE place all program text is printed from
  if ($script:Vis -and $s -match $script:RtlRe) { $s = Vis-Text $s }
  [Console]::Out.Write($s)
}
function Get-Width { try { $w = [Console]::WindowWidth; if ($w -ge 40) { return $w } } catch {}; return 80 }
function Get-Height { try { $h = [Console]::WindowHeight; if ($h -ge 10) { return $h } } catch {}; return 24 }
function Say($m)      { Out-Raw "$cGr$($Sym.bar)$cR  $m`n" }
function Bar-Line     { Out-Raw "$cGr$($Sym.bar)$cR`n" }
function Info($m)     { Say "$cC$($Sym.info)$cR $(L $m)" }
function Ok($m)       { Say "$cG$($Sym.ok)$cR $(L $m)" }
function Warn($m)     { Say "$cY$($Sym.warn)$cR $(L $m)" }
function Die($m)      { Out-Raw "$cRed$($Sym.err)  $m$cR`n$cRed$($Sym.end)$cR`n"; throw "MCSETUP_ABORT" }
function Header($t)   { Bar-Line; Out-Raw "$cG$($Sym.done)$cR  $cB$(L $t)$cR`n" }
function Write-Step([string]$t) { Header $t }
function Cancelled    { Out-Raw "`n$cY$($Sym.end)$cR  $(L 'Setup cancelled. Nothing was installed.')`n"; throw 'MCSETUP_CANCEL' }

function Show-Banner {
  $art = @(
    '███╗   ███╗██╗███╗   ██╗███████╗ ██████╗██████╗  █████╗ ███████╗████████╗',
    '████╗ ████║██║████╗  ██║██╔════╝██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝',
    '██╔████╔██║██║██╔██╗ ██║█████╗  ██║     ██████╔╝███████║█████╗     ██║   ',
    '██║╚██╔╝██║██║██║╚██╗██║██╔══╝  ██║     ██╔══██╗██╔══██║██╔══╝     ██║   ',
    '██║ ╚═╝ ██║██║██║ ╚████║███████╗╚██████╗██║  ██║██║  ██║██║        ██║   ',
    '╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   ')
  $grad = @(22, 28, 34, 40, 76, 82)
  Out-Raw "`n"
  if ($script:Utf -and (Get-Width) -ge 76) {
    for ($i = 0; $i -lt $art.Count; $i++) {
      if ($script:Color) { Out-Raw "$ESC[38;5;$($grad[$i])m$($art[$i])$cR`n" } else { Out-Raw "$($art[$i])`n" }
    }
    Out-Raw "$cGr        S E R V E R   S E T U P   W I Z A R D$cR`n"
  } else {
    Out-Raw "$cA$cB  M I N E C R A F T   S E R V E R   S E T U P$cR`n"
  }
  Out-Raw "`n"
}

function Char-Width([int]$c) {   # terminal cells a character takes: 2 for Chinese/Japanese/Korean, 0 for combining marks
  if ($c -lt 0x300) { return 1 }
  if (($c -ge 0x300 -and $c -le 0x36F) -or ($c -ge 0x900 -and $c -le 0x902) -or $c -eq 0x93C -or ($c -ge 0x941 -and $c -le 0x948) -or $c -eq 0x94D -or ($c -ge 0x951 -and $c -le 0x957) -or $c -eq 0x962 -or $c -eq 0x963 -or (Bidi-IsMark $c) -or $c -eq 0x200B -or $c -eq 0x200D) { return 0 }
  if ($c -ge 0x1100 -and ($c -le 0x115F -or ($c -ge 0x2E80 -and $c -le 0xA4CF -and $c -ne 0x303F) -or ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or ($c -ge 0xFE30 -and $c -le 0xFE6F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or ($c -ge 0xFFE0 -and $c -le 0xFFE6))) { return 2 }
  return 1
}
function Str-Width([string]$s) {
  $w = 0
  for ($i = 0; $i -lt $s.Length; $i++) {
    $c = [int]$s[$i]
    if ($c -ge 0xD800 -and $c -le 0xDBFF) { $w += 2; $i++; continue }
    $w += Char-Width $c
  }
  return $w
}
function Wrap-Text([string]$t, [int]$w) {   # wraps by display width; breaks at spaces, or between characters when there are none (Chinese/Japanese)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in ($t -split "`r?`n")) {
    if ((Str-Width $line) -le $w) { $out.Add($line); continue }
    $cur = ''; $cw = 0; $lastSp = -1
    for ($i = 0; $i -lt $line.Length; $i++) {
      $ch = [string]$line[$i]
      if ([char]::IsHighSurrogate($line[$i]) -and $i + 1 -lt $line.Length) { $ch += [string]$line[$i + 1]; $i++ }
      $wd = Str-Width $ch
      if ($cw + $wd -gt $w -and $cur.Length -gt 0) {
        if ($lastSp -gt 0) { $out.Add($cur.Substring(0, $lastSp).TrimEnd()); $cur = $cur.Substring($lastSp + 1); $cw = Str-Width $cur }
        else { $out.Add($cur); $cur = ''; $cw = 0 }
        $lastSp = -1
      }
      if ($ch -eq ' ') { if ($cur.Length -gt 0) { $lastSp = $cur.Length } else { continue } }
      $cur += $ch; $cw += $wd
    }
    if ($cur.Length -gt 0) { $out.Add($cur) }
  }
  return $out.ToArray()
}

function Done-Block([string]$title, [string]$answer) {
  Out-Raw "$cG$($Sym.done)$cR  $title`n"
  Out-Raw "$cGr$($Sym.bar)$cR  $cD$answer$cR`n"
  Bar-Line
}

# A rounded box on the timeline. A line starting with ">>" is highlighted.
function Show-Box([string]$title, [string]$body) {
  $title = L $title; $body = L $body
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($raw in ($body -split "`r?`n")) {
    if ($raw.StartsWith('>>')) {
      $r = $raw.Substring(2).TrimStart()
      foreach ($w in (Wrap-Text $r ((Get-Width) - 12))) { $lines.Add(">> $w") }
    } else { foreach ($w in (Wrap-Text $raw ((Get-Width) - 12))) { $lines.Add($w) } }
  }
  if ($script:BoxOpen) {   # wide / combining scripts: no right edge, so nothing can look misaligned
    Out-Raw "$cG$($Sym.done)$cR  $cB$title$cR`n$cGr$($Sym.bar)$cR`n"
    foreach ($l in $lines) {
      if ($l.StartsWith('>>')) { Out-Raw "$cGr$($Sym.bar)$cR  $cB$cA$($l.Substring(2).TrimStart())$cR`n" } else { Out-Raw "$cGr$($Sym.bar)$cR  $l`n" }
    }
    Out-Raw "$cGr$($Sym.bl)$cR`n"; Bar-Line; return
  }
  $w = $title.Length
  foreach ($l in $lines) { $p = $l; if ($l.StartsWith('>>')) { $p = $l.Substring(2).TrimStart() }; if ($p.Length -gt $w) { $w = $p.Length } }
  $hbar = $Sym.h * ($w + 4)
  Out-Raw "$cG$($Sym.done)$cR  $cB$title$cR $cGr$($hbar.Substring(0, $w + 1 - $title.Length))$($Sym.tr)$cR`n"
  Out-Raw "$cGr$($Sym.bar)$(' ' * ($w + 4))$($Sym.bar)$cR`n"
  foreach ($l in $lines) {
    if ($l.StartsWith('>>')) { $p = $l.Substring(2).TrimStart(); Out-Raw "$cGr$($Sym.bar)$cR  $cB$cA$p$cR$(' ' * ($w - $p.Length))  $cGr$($Sym.bar)$cR`n" }
    else { Out-Raw "$cGr$($Sym.bar)$cR  $l$(' ' * ($w - $l.Length))  $cGr$($Sym.bar)$cR`n" }
  }
  Out-Raw "$cGr$($Sym.bar)$(' ' * ($w + 4))$($Sym.bar)$cR`n"
  Out-Raw "$cGr$($Sym.bl)$hbar$($Sym.br)$cR`n"
  Bar-Line
}

# ---------------------------------------------------------------------------
#  Prompts: arrow-key lists on a real console, numbered prompts otherwise
# ---------------------------------------------------------------------------
function Ask-Menu {
  param([string]$Question, [object[]]$Options, [string]$Default)
  $tags = @(); $labels = @(); $hints = @(); $sel = 0
  for ($i = 0; $i -lt $Options.Count; $i++) {
    $t = [string]$Options[$i][0]; $d = [string]$Options[$i][1]
    $tags += $t
    if (-not $d -or $d -eq 'latest') { $labels += $t; $hints += $d } else { $labels += (L $d -NoWrap); $hints += '' }
    if ($t -eq $Default) { $sel = $i }
  }
  $n = $tags.Count
  $tl = @(Wrap-Text (L $Question) ((Get-Width) - 8))
  if ($script:Fancy) {
    $vis = [Math]::Min($n, [Math]::Max(3, [Math]::Min(12, (Get-Height) - $tl.Count - 5)))
    $more = 0; if ($vis -lt $n) { $more = 1 }
    $top = 0; $drawn = 0; $fin = $false
    Out-Raw "$ESC[?25l"
    try {
      while (-not $fin) {
        if ($sel -lt $top) { $top = $sel }
        if ($sel -ge $top + $vis) { $top = $sel - $vis + 1 }
        $sb = New-Object System.Text.StringBuilder
        if ($drawn) { [void]$sb.Append("$ESC[${drawn}A`r$ESC[J") }
        [void]$sb.Append("$cA$($Sym.act)$cR  $cB$($tl[0])$cR`n")
        for ($li = 1; $li -lt $tl.Count; $li++) { [void]$sb.Append("$cA$($Sym.bar)$cR  $cD$($tl[$li])$cR`n") }
        for ($i = $top; $i -lt $top + $vis; $i++) {
          if ($i -eq $sel) { [void]$sb.Append("$cA$($Sym.bar)$cR  $cA$($Sym.on)$cR $cB$($labels[$i])$cR $cD$($hints[$i])$cR`n") }
          else { [void]$sb.Append("$cA$($Sym.bar)$cR  $cD$($Sym.off) $($labels[$i]) $($hints[$i])$cR`n") }
        }
        if ($more) { [void]$sb.Append("$cA$($Sym.bar)$cR  $cD$($sel + 1)/$n  (up/down for more)$cR`n") }
        [void]$sb.Append("$cA$($Sym.end)$cR`n")
        Out-Raw $sb.ToString()
        $drawn = $tl.Count + $vis + $more + 1
        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
          'UpArrow'   { if ($sel -gt 0) { $sel-- } else { $sel = $n - 1 } }
          'DownArrow' { if ($sel -lt $n - 1) { $sel++ } else { $sel = 0 } }
          'Home'      { $sel = 0 }
          'End'       { $sel = $n - 1 }
          'Enter'     { $fin = $true }
          default {
            if ($k.KeyChar -eq 'k') { if ($sel -gt 0) { $sel-- } else { $sel = $n - 1 } }
            elseif ($k.KeyChar -eq 'j') { if ($sel -lt $n - 1) { $sel++ } else { $sel = 0 } }
          }
        }
      }
    } finally { Out-Raw "$ESC[?25h" }
    Out-Raw "$ESC[${drawn}A`r$ESC[J"
    Done-Block $tl[0] $labels[$sel]
    return $tags[$sel]
  }
  # numbered fallback
  Out-Raw "$cA$($Sym.act)$cR  $cB$($tl[0])$cR`n"
  for ($li = 1; $li -lt $tl.Count; $li++) { Say "$cD$($tl[$li])$cR" }
  for ($i = 0; $i -lt $n; $i++) { Say ('{0,2}) {1} {2}' -f ($i + 1), $labels[$i], $hints[$i]) }
  $defNum = $sel + 1
  while ($true) {
    Out-Raw "$cGr$($Sym.bar)$cR  Choose [$defNum]: "
    $a = [Console]::In.ReadLine()
    if ($null -eq $a) { Cancelled }
    if ($a -eq '') { $a = "$defNum" }
    $num = 0
    if ([int]::TryParse($a, [ref]$num) -and $num -ge 1 -and $num -le $n) { Bar-Line; return $tags[$num - 1] }
    foreach ($t in $tags) { if ($t -eq $a) { Bar-Line; return $a } }
    if ($tags[0] -eq 'yes') { if ($a -match '^(?i)y') { Bar-Line; return 'yes' }; if ($a -match '^(?i)n') { Bar-Line; return 'no' } }
    Say 'Please type a number from the list.'
  }
}

function Ask-YesNo {
  param([string]$Question, [bool]$Default = $true)
  $d = 'no'; if ($Default) { $d = 'yes' }
  return ((Ask-Menu $Question @(@('yes', 'Yes'), @('no', 'No')) $d) -eq 'yes')
}

# Tick-box list. $Items = @(@(tag, label), ...). Returns the ticked tags.
function Ask-Multi {
  param([string]$Question, [object[]]$Items)
  $n = $Items.Count; $ticked = New-Object 'bool[]' $n; $sel = 0
  $tl = @(Wrap-Text (L $Question) ((Get-Width) - 8))
  if ($script:Fancy) {
    $vis = [Math]::Min($n, [Math]::Max(3, [Math]::Min(14, (Get-Height) - $tl.Count - 5)))
    $more = 0; if ($vis -lt $n) { $more = 1 }
    $top = 0; $drawn = 0; $fin = $false
    Out-Raw "$ESC[?25l"
    try {
      while (-not $fin) {
        if ($sel -lt $top) { $top = $sel }
        if ($sel -ge $top + $vis) { $top = $sel - $vis + 1 }
        $sb = New-Object System.Text.StringBuilder
        if ($drawn) { [void]$sb.Append("$ESC[${drawn}A`r$ESC[J") }
        [void]$sb.Append("$cA$($Sym.act)$cR  $cB$($tl[0])$cR`n")
        for ($li = 1; $li -lt $tl.Count; $li++) { [void]$sb.Append("$cA$($Sym.bar)$cR  $cD$($tl[$li])$cR`n") }
        for ($i = $top; $i -lt $top + $vis; $i++) {
          if ($ticked[$i]) { $box = "$cG$($Sym.boxon)$cR" } else { $box = "$cD$($Sym.boxoff)$cR" }
          if ($i -eq $sel) { [void]$sb.Append("$cA$($Sym.bar)$cR  $box $cB$cA$($Items[$i][1])$cR`n") }
          else { [void]$sb.Append("$cA$($Sym.bar)$cR  $box $cD$($Items[$i][1])$cR`n") }
        }
        if ($more) { [void]$sb.Append("$cA$($Sym.bar)$cR  $cD$($sel + 1)/$n  (up/down for more)$cR`n") }
        [void]$sb.Append("$cA$($Sym.end)$cR`n")
        Out-Raw $sb.ToString()
        $drawn = $tl.Count + $vis + $more + 1
        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
          'UpArrow'   { if ($sel -gt 0) { $sel-- } else { $sel = $n - 1 } }
          'DownArrow' { if ($sel -lt $n - 1) { $sel++ } else { $sel = 0 } }
          'Spacebar'  { $ticked[$sel] = -not $ticked[$sel] }
          'Enter'     { $fin = $true }
          default {
            if ($k.KeyChar -eq 'a' -or $k.KeyChar -eq 'A') { $all = -not ($ticked -contains $false); for ($i = 0; $i -lt $n; $i++) { $ticked[$i] = -not $all } }
            elseif ($k.KeyChar -eq 'k') { if ($sel -gt 0) { $sel-- } else { $sel = $n - 1 } }
            elseif ($k.KeyChar -eq 'j') { if ($sel -lt $n - 1) { $sel++ } else { $sel = 0 } }
          }
        }
      }
    } finally { Out-Raw "$ESC[?25h" }
    Out-Raw "$ESC[${drawn}A`r$ESC[J"
  } else {
    Out-Raw "$cA$($Sym.act)$cR  $cB$($tl[0])$cR`n"
    for ($i = 0; $i -lt $n; $i++) { Say ('{0,2}) {1}' -f ($i + 1), $Items[$i][1]) }
    Out-Raw "$cGr$($Sym.bar)$cR  Numbers separated by spaces (e.g. 1 4 7), or Enter for none: "
    $a = [Console]::In.ReadLine()
    if ($null -eq $a) { Cancelled }
    foreach ($x in ($a -split '[\s,]+' | Where-Object { $_ })) { $num = 0; if ([int]::TryParse($x, [ref]$num) -and $num -ge 1 -and $num -le $n) { $ticked[$num - 1] = $true } }
  }
  $picked = @(); for ($i = 0; $i -lt $n; $i++) { if ($ticked[$i]) { $picked += [string]$Items[$i][0] } }
  $title = $tl[0] -replace ' \(.*$', ''
  $ans = '(none)'; if ($picked.Count) { $ans = $picked -join ' ' }
  Done-Block $title $ans
  return $picked
}

function Ask-Text {
  param([string]$Question, [string]$Default = '', [switch]$Secret)
  $tl = @(Wrap-Text (L $Question) ((Get-Width) - 8))
  if ($script:Fancy) {
    Out-Raw "$cA$($Sym.act)$cR  $cB$($tl[0])$cR`n"
    for ($li = 1; $li -lt $tl.Count; $li++) { Out-Raw "$cA$($Sym.bar)$cR  $cD$($tl[$li])$cR`n" }
    $buf = $Default; if ($Secret) { $buf = '' }
    while ($true) {
      $shown = $buf; if ($Secret) { $shown = '*' * $buf.Length }
      Out-Raw "`r$ESC[K$cA$($Sym.bar)$cR  $shown"
      $k = [Console]::ReadKey($true)
      if ($k.Key -eq 'Enter') { break }
      elseif ($k.Key -eq 'Backspace') { if ($buf.Length) { $buf = $buf.Substring(0, $buf.Length - 1) } }
      elseif ($k.Key -eq 'Escape' -or $k.KeyChar -eq [char]21) { $buf = '' }
      elseif (-not [char]::IsControl($k.KeyChar)) { $buf += $k.KeyChar }
    }
    $shown = $buf; if ($Secret) { $shown = '*' * $buf.Length }
    $up = $tl.Count + [int][Math]::Floor((3 + $shown.Length) / (Get-Width))
    Out-Raw "`r$ESC[${up}A$ESC[J"
    if ($Secret) { Done-Block $tl[0] '(hidden)' } else { Done-Block $tl[0] $buf }
    return $buf
  }
  Out-Raw "$cA$($Sym.act)$cR  $cB$($tl[0])$cR`n"
  for ($li = 1; $li -lt $tl.Count; $li++) { Say "$cD$($tl[$li])$cR" }
  $shownDef = $Default; if ($Secret) { $shownDef = 'hidden' }
  Out-Raw "$cGr$($Sym.bar)$cR  [$shownDef]: "
  $a = [Console]::In.ReadLine()
  if ($null -eq $a) { Cancelled }
  Bar-Line
  if ($a -eq '') { return $Default }
  return $a
}

# ---------------------------------------------------------------------------
#  Network helpers
# ---------------------------------------------------------------------------
function Get-Json($url) {
  for ($i = 1; $i -le 3; $i++) {
    try { return Invoke-RestMethod -Uri $url -UserAgent $UA -UseBasicParsing -TimeoutSec 30 }
    catch { if ($i -eq 3) { throw }; Start-Sleep -Seconds 2 }
  }
}
function Get-File($url, $dest) {
  $name = Split-Path $dest -Leaf
  $part = "$dest.part"
  for ($try = 1; $try -le 3; $try++) {
    try {
      if (-not $script:Fancy) {
        Info "Downloading $name ..."
        Invoke-WebRequest -Uri $url -OutFile $part -UserAgent $UA -UseBasicParsing -TimeoutSec 600
        break
      }
      $req = [Net.HttpWebRequest]::Create($url); $req.UserAgent = $UA; $req.AllowAutoRedirect = $true; $req.Timeout = 60000; $req.ReadWriteTimeout = 60000
      $resp = $req.GetResponse(); $total = $resp.ContentLength
      $in = $resp.GetResponseStream(); $out = [IO.File]::Create($part)
      try {
        $buf = New-Object byte[] 81920; $got = 0L; $sw = [Diagnostics.Stopwatch]::StartNew(); $last = -1000; $f = 0
        while (($r = $in.Read($buf, 0, $buf.Length)) -gt 0) {
          $out.Write($buf, 0, $r); $got += $r
          if (($sw.ElapsedMilliseconds - $last) -ge 100) {
            $last = $sw.ElapsedMilliseconds; $f = ($f + 1) % $script:Spin.Count
            $mb = '{0:N1}' -f ($got / 1MB)
            if ($total -gt 0) {
              $pct = [int](100 * $got / $total); $fill = [int](24 * $got / $total)
              $barS = ($Sym.full * $fill) + ($Sym.empty * (24 - $fill))
              Out-Raw "`r$ESC[K$cGr$($Sym.bar)$cR  $cA$($script:Spin[$f])$cR $name  $cA$barS$cR $pct%  ($mb / $('{0:N1}' -f ($total / 1MB)) MB)"
            } else { Out-Raw "`r$ESC[K$cGr$($Sym.bar)$cR  $cA$($script:Spin[$f])$cR $name  $mb MB" }
          }
        }
      } finally { $out.Close(); $in.Close(); $resp.Close() }
      Out-Raw "`r$ESC[K"
      Ok ("$name  ({0:N1} MB)" -f ((Get-Item $part).Length / 1MB))
      break
    } catch { Remove-Item -Force -ErrorAction SilentlyContinue $part; if ($try -eq 3) { if ($script:Fancy) { Out-Raw "`r$ESC[K" }; throw }; Start-Sleep -Seconds 2 }
  }
  Move-Item -Force $part $dest
}
function Test-Hash($file, $algo, $expected) {
  if (-not $expected) { return }
  $got = (Get-FileHash -Algorithm $algo -Path $file).Hash.ToLower()
  if ($got -ne $expected.ToLower()) { Die "Checksum mismatch for $file (expected $expected, got $got)." }
  Ok "Checksum OK ($algo)"
}

function Compare-Ver($a, $b) {   # returns $true if $a >= $b (numeric parts)
  $pa = @($a -split '[.\-]' | ForEach-Object { $n = 0; [void][int]::TryParse($_, [ref]$n); $n })
  $pb = @($b -split '[.\-]' | ForEach-Object { $n = 0; [void][int]::TryParse($_, [ref]$n); $n })
  for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
    $x = 0; $y = 0
    if ($i -lt $pa.Count) { $x = $pa[$i] }
    if ($i -lt $pb.Count) { $y = $pb[$i] }
    if ($x -gt $y) { return $true }
    if ($x -lt $y) { return $false }
  }
  return $true
}

$IsArm = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') -or ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')
$ArchJdk = 'x64'; if ($IsArm) { $ArchJdk = 'aarch64' }

# ---------------------------------------------------------------------------
#  Version lookups
# ---------------------------------------------------------------------------
$script:Manifest = $null
function Get-Manifest { if (-not $script:Manifest) { $script:Manifest = Get-Json $MojangManifest }; return $script:Manifest }
function Get-VanillaVersions { @((Get-Manifest).versions | Where-Object { $_.type -eq 'release' } | ForEach-Object { $_.id }) }
function Get-PaperVersions {
  $p = Get-Json "$PaperApi/paper"
  @($p.versions.PSObject.Properties | ForEach-Object { $_.Value } | ForEach-Object { $_ } | Where-Object { $_ -notmatch '-(rc|pre)' })
}
function Get-VelocityLatest {
  $p = Get-Json "$PaperApi/velocity"
  @($p.versions.PSObject.Properties | ForEach-Object { $_.Value } | ForEach-Object { $_ } | Where-Object { $_ -notmatch 'SNAPSHOT' })[0]
}
function Get-MojangVersionJson($id) {
  $v = (Get-Manifest).versions | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $v) { return $null }
  return Get-Json $v.url
}
function Get-JavaForMc($ver) {
  try { $j = (Get-MojangVersionJson $ver).javaVersion.majorVersion; if ($j) { return [int]$j } } catch {}
  if (Compare-Ver $ver '26.0')   { return 25 }
  if (Compare-Ver $ver '1.20.5') { return 21 }
  if (Compare-Ver $ver '1.18')   { return 17 }
  if (Compare-Ver $ver '1.17')   { return 16 }
  return 8
}
function Select-Version($label, [string[]]$all) {
  if ($all.Count -eq 0) { Die "Could not get the $label version list (network problem?)." }
  $opts = @()
  for ($i = 0; $i -lt [Math]::Min(15, $all.Count); $i++) {
    $d = ''; if ($i -eq 0) { $d = L 'Newest (recommended)' }
    $opts += ,@($all[$i], $d)
  }
  $opts += ,@('other', 'Type a specific older version')
  $c = Ask-Menu 'Which Minecraft version? (newest first)' $opts $all[0]
  while ($c -eq 'other') {
    $c = Ask-Text 'Type the exact Minecraft version (e.g. 1.20.1):' $all[0]
    if ($all -notcontains $c) {
      Say (L 'That version is not available. Pick one from the list instead.'); Bar-Line
      $c = Ask-Menu 'Which Minecraft version? (newest first)' $opts $all[0]
    }
  }
  return $c
}

# ---------------------------------------------------------------------------
#  Java
# ---------------------------------------------------------------------------
function Get-JavaMajor($exe) {
  try {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = (& $exe -version 2>&1 | Out-String)
    $ErrorActionPreference = $old
  } catch { return 0 }
  if ($out -match 'version "([^"]+)"') {
    $v = $Matches[1]
    if ($v.StartsWith('1.')) { return [int]($v.Split('.')[1]) }
    return [int](($v -split '[.+\-]')[0])
  }
  return 0
}
function Ensure-Java([int]$req) {
  $cmd = Get-Command java -ErrorAction SilentlyContinue
  if ($cmd) {
    $sys = Get-JavaMajor $cmd.Source
    if ($sys -ge $req) { Info "Using system Java $sys (needs $req+)."; return $cmd.Source }
    Warn "System Java is $sys but this server needs Java $req+."
  }
  $feat = $req; if ($feat -eq 16) { $feat = 17 }
  $dir = Join-Path $InstallDir "java\jre-$feat"
  $exe = Join-Path $dir 'bin\java.exe'
  if (Test-Path $exe) { return $exe }
  Info "Downloading Eclipse Temurin Java $feat (into $InstallDir\java, no admin needed) ..."
  New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'java') | Out-Null
  $zip = Join-Path $InstallDir "java\temurin-$feat.zip"
  $got = $false
  foreach ($kind in @('jre', 'jdk')) {
    try { Get-File "$AdoptiumApi/$feat/ga/windows/$ArchJdk/$kind/hotspot/normal/eclipse" $zip; $got = $true; break } catch {}
  }
  if (-not $got) { Die "Could not download Java $feat. Install it from https://adoptium.net and run again." }
  $tmp = Join-Path $InstallDir "java\_extract"
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
  if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
  Move-Item $inner.FullName $dir
  Remove-Item -Recurse -Force $tmp, $zip
  if (-not (Test-Path $exe)) { Die 'Java download looks broken.' }
  Ok "Java $feat installed at $dir"
  return $exe
}

# ---------------------------------------------------------------------------
#  Server downloads
# ---------------------------------------------------------------------------
function Get-Vanilla($ver, $dest) {
  $vj = Get-MojangVersionJson $ver
  if (-not $vj -or -not $vj.downloads.server) { Die "Mojang has no server download for $ver." }
  Get-File $vj.downloads.server.url $dest
  Test-Hash $dest 'SHA1' $vj.downloads.server.sha1
}
function Get-PaperMC($project, $ver, $dest) {
  try { $b = Get-Json "$PaperApi/$project/versions/$ver/builds/latest" } catch { Die "PaperMC has no $project build for $ver." }
  $d = $b.downloads.'server:default'
  if (-not $d) { Die "No download URL in PaperMC response for $project $ver." }
  if ($b.channel -ne 'STABLE') { Warn "$project $ver build $($b.id) is marked $($b.channel) (not STABLE)." }
  Info "$project $ver build #$($b.id)"
  Get-File $d.url $dest
  Test-Hash $dest 'SHA256' $d.checksums.sha256
}

# ---------------------------------------------------------------------------
#  File writers (UTF-8 without BOM - Java configs dislike a BOM)
# ---------------------------------------------------------------------------
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Text($path, [string]$text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), $Utf8NoBom) }
function Write-Unix($path, [string]$text) { [IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"), $Utf8NoBom) }

function ConvertTo-MotdProps([string]$m) { return (($m -replace '&([0-9a-fk-orA-FK-OR])', '@@SEC@@$1').Replace('@@SEC@@', '\u00A7')) }   # &6 -> section-sign escape

function Write-ServerProperties($dir, $ip, $port, $online) {
  $o = $online.ToString().ToLower()
  $f = Join-Path $dir 'server.properties'
  $b = { param($v) $v.ToString().ToLower() }
  Write-Unix $f @"
# Generated by mc-setup.ps1 on $(Get-Date)
motd=$(ConvertTo-MotdProps $Motd)
server-ip=$ip
server-port=$port
online-mode=$o
max-players=$MaxPlayers
gamemode=$Gamemode
force-gamemode=$(& $b $script:ForceGm)
difficulty=$Difficulty
hardcore=$(& $b $script:Hardcore)
pvp=$(& $b $script:Pvp)
white-list=$(& $b $Whitelist)
enforce-whitelist=$(& $b $Whitelist)
view-distance=$script:ViewDist
simulation-distance=$script:SimDist
spawn-protection=$script:SpawnProt
enable-command-block=$(& $b $script:CmdBlocks)
allow-flight=$(& $b $script:AllowFlight)
allow-nether=$(& $b $script:AllowNether)
generate-structures=$(& $b $script:GenStruct)
spawn-animals=$(& $b $script:SpawnAnimals)
spawn-monsters=$(& $b $script:SpawnMonsters)
spawn-npcs=$(& $b $script:SpawnNpcs)
player-idle-timeout=$script:IdleTimeout
level-name=$script:LevelName
level-seed=$Seed
level-type=minecraft\:$script:LevelType
resource-pack=$script:ResPackUrl
resource-pack-sha1=$script:ResPackSha1
require-resource-pack=$(& $b $script:ResPackReq)
enforce-secure-profile=$o
"@
  foreach ($kv in $script:ExtraProps) {
    $k = $kv.Split('=')[0]
    $lines = @(Get-Content $f | Where-Object { -not $_.StartsWith("$k=") })
    $lines += $kv
    Write-Unix $f (($lines -join "`n") + "`n")
  }
  Write-Unix (Join-Path $dir 'eula.txt') "eula=true`n"
}

$AikarFlags = '-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1'

# Can this Java start with these flags? (a flag the JVM doesn't know makes it refuse to start)
function Test-JvmFlags($java, [string]$flags) {
  try { cmd /c "`"$java`" $flags -version >nul 2>&1"; return ($LASTEXITCODE -eq 0) } catch { return $false }
}
function Write-StartBat($dir, $java, $xmx, $xms, $flags, $launch, $title) {
  if ($flags -and -not (Test-JvmFlags $java $flags)) {
    Warn 'This Java does not accept some of the tuning flags - using a simple, safe set instead.'
    $flags = '-XX:+UseG1GC'
  }
  $run = "`"$java`" -Xms${xms}M -Xmx${xmx}M $flags $launch"
  if ($script:AutoRestart) {
    $body = @"
:again
$run
if %errorlevel%==0 goto done
echo.
echo [$title stopped with an error ^(code %errorlevel%^). Scroll up to see why. Restarting in 10 seconds - close this window to cancel]
timeout /t 10 /nobreak >nul
goto again
:done
"@
  } else { $body = $run }
  Write-Text (Join-Path $dir 'start.bat') @"
@echo off
rem Starts this server. Generated by mc-setup.ps1
title $title
cd /d "%~dp0"
$body
set CODE=%errorlevel%
echo.
if not "%CODE%"=="0" (
  echo [$title stopped with an error - code %CODE%]
  echo What this usually means:
  echo   - "Could not create the Java Virtual Machine": the Java or memory settings are wrong.
  echo     Lower RAM in mc-setup, or re-run mc-setup to pick a matching Java.
  echo   - "Address already in use": another server is already running on this port.
  echo   - "Unsupported class file" / "requires Java": wrong Java version for this Minecraft.
  echo The exact message is just above this text, and logs\latest.log has more.
) else (
  echo [$title stopped]
)
pause
"@
}

function Set-VelocityConfig($d, $java) {
  $f = Join-Path $d 'velocity.toml'
  Info 'Generating default Velocity config (first launch, takes a few seconds) ...'
  $log = Join-Path $d 'first-run.log'
  $p = Start-Process -FilePath $java -ArgumentList '-Xmx256M', '-jar', 'velocity.jar' -WorkingDirectory $d `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -WindowStyle Hidden
  for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 1
    if ((Test-Path $log) -and (Select-String -Path $log -Pattern 'Done' -Quiet)) { break }
    if ($p.HasExited) { break }
  }
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }

  $secretFile = Join-Path $d 'forwarding.secret'
  $onl = $Online.ToString().ToLower()
  $motdT = $Motd -replace '"', ''
  if (-not (Test-Path $f)) {
    Warn 'Velocity did not create a config; writing a minimal one.'
    Write-Unix $f @"
config-version = "2.7"
bind = "0.0.0.0:$Port"
motd = "$motdT"
show-max-players = $MaxPlayers
online-mode = $onl
force-key-authentication = $onl
player-info-forwarding-mode = "modern"
forwarding-secret-file = "forwarding.secret"

[servers]
lobby = "127.0.0.1:$BackendPort"
try = ["lobby"]

[forced-hosts]
"@
  } else {
    $out = New-Object System.Collections.Generic.List[string]
    $sec = ''; $skip = $false
    foreach ($line in (Get-Content $f)) {
      if ($line -match '^\[') { $sec = $line.Trim() }
      if ($sec -eq '') {
        if     ($line -match '^bind\s*=')                         { $line = "bind = `"0.0.0.0:$Port`"" }
        elseif ($line -match '^online-mode\s*=')                  { $line = "online-mode = $onl" }
        elseif ($line -match '^force-key-authentication\s*=')     { $line = "force-key-authentication = $onl" }
        elseif ($line -match '^player-info-forwarding-mode\s*=')  { $line = 'player-info-forwarding-mode = "modern"' }
        elseif ($line -match '^show-max-players\s*=')             { $line = "show-max-players = $MaxPlayers" }
        elseif ($line -match '^motd\s*=')                         { $line = "motd = `"$motdT`"" }
        $out.Add($line); continue
      }
      if ($sec -eq '[servers]' -or $sec -eq '[forced-hosts]') {
        if ($line -match '^\[') {
          $out.Add($line)
          if ($sec -eq '[servers]') { $out.Add("lobby = `"127.0.0.1:$BackendPort`""); $out.Add('try = ["lobby"]') }
          continue
        }
        if ($skip) { if ($line -match '\]') { $skip = $false }; continue }
        if ($line -match '=') { $skip = ($line -match '=\s*\[' -and $line -notmatch '\]'); continue }
      }
      $out.Add($line)
    }
    Write-Unix $f (($out -join "`n") + "`n")
  }
  if (-not (Test-Path $secretFile)) {
    $chars = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    Write-Unix $secretFile (-join (1..16 | ForEach-Object { $chars | Get-Random }))
  }
  Remove-Item -Force -ErrorAction SilentlyContinue $log, "$log.err"
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $d 'logs')
  Ok "Velocity configured (modern forwarding -> 127.0.0.1:$BackendPort)"
}

function Set-PaperVelocity($d, $secret) {
  $onl = $Online.ToString().ToLower()
  if (Compare-Ver $McVersion '1.19') {
    New-Item -ItemType Directory -Force -Path (Join-Path $d 'config') | Out-Null
    Write-Unix (Join-Path $d 'config\paper-global.yml') @"
# Partial config written by mc-setup.ps1 - Paper fills in the rest on first start
proxies:
  velocity:
    enabled: true
    online-mode: $onl
    secret: '$secret'
"@
  } else {
    Write-Unix (Join-Path $d 'paper.yml') @"
# Partial config written by mc-setup.ps1 - Paper fills in the rest on first start
settings:
  velocity-support:
    enabled: true
    online-mode: $onl
    secret: '$secret'
"@
  }
  Ok 'Paper backend set to accept Velocity modern forwarding'
}

# ---------------------------------------------------------------------------
#  Networking
# ---------------------------------------------------------------------------
function Get-LanIp {
  try {
    $r = Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if ($r) { return $r.IPv4Address.IPAddress }
  } catch {}
  try {
    $s = New-Object System.Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Dgram, [Net.Sockets.ProtocolType]::Udp)
    $s.Connect('1.1.1.1', 53); $ip = $s.LocalEndPoint.Address.ToString(); $s.Close(); return $ip
  } catch { return '<this-pc-ip>' }
}
function Get-PublicIp {
  foreach ($u in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
    try { return (Invoke-RestMethod -Uri $u -TimeoutSec 6 -UseBasicParsing).ToString().Trim() } catch {}
  }
  return 'unknown'
}

function Open-Firewall($port, [string]$proto = 'TCP') {
  $name = "Minecraft $port $proto"
  $cmd = "if (-not (Get-NetFirewallRule -DisplayName '$name' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName '$name' -Direction Inbound -Protocol $proto -LocalPort $port -Action Allow | Out-Null }"
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  try {
    if ($isAdmin) { Invoke-Expression $cmd }
    else {
      Info 'Asking for administrator permission to add a Windows Firewall rule (click Yes) ...'
      $p = Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList '-NoProfile', '-Command', $cmd
      if ($p.ExitCode -ne 0) { throw "exit $($p.ExitCode)" }
    }
    Ok "Windows Firewall: allowed inbound $proto $port"
  } catch {
    Warn "Could not add the firewall rule. When Java first starts, Windows may ask - click 'Allow access'."
  }
}

function Add-UPnP($port, [string]$proto = 'TCP') {
  try {
    $nat = New-Object -ComObject HNetCfg.NATUPnP
    $maps = $nat.StaticPortMappingCollection
    if ($null -eq $maps) { throw 'no UPnP router found' }
    $ip = Get-LanIp
    try { $maps.Remove($port, $proto) } catch {}
    [void]$maps.Add($port, $proto, $port, $ip, $true, 'Minecraft')
    Ok "UPnP: router now forwards $proto $port -> ${ip}:$port"
    return $true
  } catch {
    Warn "UPnP did not work ($($_.Exception.Message)). See the manual steps at the end."
    return $false
  }
}

# ---------------------------------------------------------------------------
#  playit.gg tunnel guide: one small step per screen
# ---------------------------------------------------------------------------
$script:PublicAddr = ''
function Open-Url([string]$u) {
  try { Start-Process $u } catch { Say "Open this link in your browser:  $u" }
}
function Start-TunnelGuide {
  $steps = @(
    @{ T = 'What we are going to do'; U = ''; B = @'
A tunnel lets friends reach your server over the internet without touching your router. playit.gg is free and needs no credit card.

You will do 7 small things:
 1. Make a free playit.gg account
 2. Install the playit program on this PC
 3. Connect (claim) this PC to your account
 4. Create a Minecraft tunnel
 5. Copy the address playit gives you
 6. Paste it here so it is saved
 7. Test it

It takes about 10 minutes. Each screen is one small step. Do it, then press Enter on 'Done'. You can go Back any time.
'@ },
    @{ T = 'Make your free playit.gg account'; U = 'https://playit.gg/'; B = @'
1. Open https://playit.gg  (choose 'Open the page for me' below if you like).
2. Click the 'Login' button at the top right.
3. Click 'Create an account' and sign up with Google, Discord or an email and password.
4. If it asks you to verify your email, open your email, click the link, then come back to the site.
>> You should now see your playit.gg dashboard (a page with a menu on the left).

If you already have an account: just log in and go to the next step.
If you did not get the email: check Spam, or wait 2 minutes and click 'resend'.
'@ },
    @{ T = 'Download and install playit'; U = 'https://playit.gg/download'; B = @'
1. Open https://playit.gg/download
2. Under Windows, click the main download (the installer, ends in .msi).
>> Easier alternative: open a terminal and type   winget install DevelopedMethods.playit
3. Double-click the downloaded file. Click Yes if Windows asks permission.
4. Click Next, then Install, then Finish.
>> It installs the playit program and a small tray icon. Nothing else to configure.

If you see 'Windows protected your PC': click 'More info', then 'Run anyway'.
If your antivirus complains: playit is a well known program, choose 'allow'.
'@ },
    @{ T = 'Open playit and get the claim link'; U = ''; B = @'
1. Open the Start menu, type  playit  and open 'Playit.gg'.
   (Or click the playit icon near the clock at the bottom right. It may hide behind the ^ arrow.)
2. A playit window opens.
>> You should see a message that this computer is not linked yet, with a link like  https://playit.gg/claim/xxxxxx  or a short code.

If no window appears: wait 20 seconds, then try the Start menu again.
If it says 'Could not connect to the playit service': restart the PC once, then open playit again.
If the link is not visible: click the playit window and look for a button 'Claim' or 'Open link'.
'@ },
    @{ T = 'Claim this computer'; U = ''; B = @'
1. Click the claim link in the playit window, or copy it into your web browser.
2. Make sure you are logged in to playit.gg (step 2).
3. Click the button 'Add Agent' (it may say 'Approve' or 'Claim').
4. Go back to the playit window.
>> You should see it change to 'Connected' or 'Online' (a green status).

If the page says 'invalid' or 'expired': go back to the playit window, get a fresh link and try again.
If it never turns green after 1 minute: check your internet, then close and reopen playit.
'@ },
    @{ T = 'Create your Minecraft tunnel'; U = 'https://playit.gg/account/setup/new-tunnel'; B = @'
1. Open https://playit.gg/account/setup/new-tunnel  (or on the dashboard click 'Create tunnel').
2. Tunnel type:  choose  Minecraft Java.
3. Region:  pick the one closest to you and your friends. 'Global' is free and fine.
4. Agent:  pick the computer you just added (it has a green dot).
5. Local address (type exactly this):
>> 127.0.0.1
6. Local port (your server port):
>> {PORT}
7. Click 'Create tunnel' (or 'Add tunnel').
>> You should now see your new tunnel in a list, marked as active.

If the port box is not shown: open the tunnel after creating it and click its Edit or 'Origin' settings.
If it says 'free limit reached': delete an old tunnel on the same page first.
'@ },
    @{ T = 'Copy your public address'; U = 'https://playit.gg/account/tunnels'; B = @'
1. Open https://playit.gg/account/tunnels  (left menu: 'Tunnels') and click your Minecraft tunnel.
2. Find the field called 'Address' or 'Allocation' (also called Shared IP).
>> It looks like  something.joinmc.link  or  12.ip.gl.ply.gg:34567
3. Click it to copy. Keep the number after the colon if there is one!

If you see two addresses: use the one for 'Minecraft Java'.
If the address says 'pending' or 'allocating': wait a minute and refresh the page.
'@ },
    @{ T = 'Paste the address here'; U = ''; B = @'
NEXT SCREEN asks for the address you copied. Paste it with right-click (or Ctrl+V; in Windows Terminal also Ctrl+Shift+V).
It is saved, shown in your final summary, and remembered for later.

If you do not have it yet: go Back one step.
'@ },
    @{ T = 'Test it'; U = ''; B = @'
1. Start your server: double-click  start-all.bat  in your server folder.
   Wait until the server window says  Done  (about a minute the first time).
2. Open Minecraft Java Edition and click Multiplayer, then 'Add Server'.
3. Paste your playit address in 'Server Address', click Done, then double-click the server.
>> You should see your server name and join.

Friends do exactly the same with the same address. They install nothing.

If it says 'Can't connect to server':
 - Is the server window still open and finished starting?
 - Is playit online (green) and the tunnel active on playit.gg?
 - Is the tunnel port {PORT} the same as your server port?
 - Did you copy the number after the colon?
 - Do you and your friends use the same Minecraft version as the server?
Still stuck? Run mc-setup again and choose an ngrok tunnel or router port forwarding instead.
'@ }
)
  $pasteI = 7
  if ($script:Bedrock) {
    $steps[8].B = $steps[8].B.Replace('They install nothing.', "They install nothing.`nBedrock players: open Minecraft Bedrock, Play > Servers > Add Server. Type the Bedrock address in 'Server Address' and its port number in 'Port' (two separate boxes). Join as usual.")
    $bed = @{ T = 'Add a second tunnel for Bedrock players'; U = 'https://playit.gg/account/setup/new-tunnel'; B = @'
Bedrock players (phones, consoles, Windows 10/11) use UDP, so they need their own tunnel.
1. Open https://playit.gg/account/setup/new-tunnel  (or click 'Create tunnel' again).
2. Tunnel type:  choose  Minecraft Bedrock.
3. Region and Agent:  the same as for the Java tunnel.
4. Local address (type exactly this):
>> 127.0.0.1
5. Local port (Geyser's port):
>> {BPORT}
6. Click 'Create tunnel'.
7. On https://playit.gg/account/tunnels open the Bedrock tunnel and copy its address and port.
>> It looks like  something.joinmc.link  and a port number such as  34567.

If it says 'free limit reached': delete an old tunnel on the same page first.
'@ }
    $steps = @($steps[0..6]) + @($bed) + @($steps[7..($steps.Count - 1)])
    $pasteI = 8
  }
  $n = $steps.Count; $i = 0
  while ($i -lt $n) {
    Show-Box "Step $($i + 1) of $n - $($steps[$i].T)" ($steps[$i].B.Replace('{PORT}', "$Port").Replace('{BPORT}', "$($script:BedrockPort)").Replace('{START}', 'start-all.bat'))
    if ($i -eq $pasteI) {   # the paste step
      $a = (Ask-Text 'Paste your playit address here (or press Enter to do it later)' $script:PublicAddr) -replace '\s', ''
      $a = $a -replace '^minecraft://', ''
      if ($a) { $script:PublicAddr = $a; Ok "Saved: $a" }
      if ($script:Bedrock) {
        $a = (Ask-Text 'Paste your Bedrock address here, with its port (for example  something.joinmc.link:34567)' $script:PublicAddrBe) -replace '\s', ''
        if ($a) { $script:PublicAddrBe = $a; Ok "Saved: $a" }
      }
      $i++; continue
    }
    $opts = @(, @('next', 'Done - go to the next step'))
    if ($steps[$i].U) { $opts += , @('open', 'Open the page for me') }
    if ($i -gt 0) { $opts += , @('back', 'Go back one step') }
    $opts += , @('quit', 'Skip the rest (I will do it later)')
    $c = Ask-Menu 'What now?' $opts 'next'
    switch ($c) {
      'next' { $i++ }
      'open' { Open-Url $steps[$i].U }
      'back' { $i-- }
      'quit' { $i = $n }
    }
  }
  if ($script:PublicAddr) {
    Say "Your public address: $($script:PublicAddr)   (friends use this to join)"; Bar-Line
    if ($script:PublicAddrBe) { Say "Your Bedrock address: $($script:PublicAddrBe)   (Bedrock players use this)"; Bar-Line }
  }
  else { Say 'No problem. Run  powershell -File mc-setup.ps1 -TunnelGuide  any time to continue.'; Bar-Line }
}

function Install-Geyser([string]$srvDir) {   # Geyser + Floodgate for Bedrock players (Paper)
  $d = Join-Path $srvDir 'plugins'; $gd = Join-Path $d 'Geyser-Spigot'
  New-Item -ItemType Directory -Force -Path $d, $gd | Out-Null
  $base = 'https://download.geysermc.org/v2/projects'
  Info 'Downloading Geyser and Floodgate (Bedrock support) ...'
  Get-File "$base/geyser/versions/latest/builds/latest/downloads/spigot" (Join-Path $d 'Geyser-Spigot.jar')
  Get-File "$base/floodgate/versions/latest/builds/latest/downloads/spigot" (Join-Path $d 'floodgate-spigot.jar')
  # Bedrock port, and let Floodgate log Bedrock players in (no Java account needed)
  Write-Unix (Join-Path $gd 'config.yml') "bedrock:`n  port: $($script:BedrockPort)`n  clone-remote-port: false`njava:`n  auth-type: floodgate`n"
  Ok (Lf 'Bedrock support installed (Geyser + Floodgate, UDP {0})' $script:BedrockPort)
}

function Install-Playit {
  # playit 2.x is installed as a normal Windows program (with a tray icon), so there is nothing to download here:
  # the guide walks through installing it.
  Ok 'playit.gg selected - a step-by-step guide follows'
}

function Install-Ngrok {
  $tools = Join-Path $InstallDir 'tools'
  New-Item -ItemType Directory -Force -Path $tools | Out-Null
  $arch = 'amd64'; if ($IsArm) { $arch = 'arm64' }
  $zip = Join-Path $tools 'ngrok.zip'
  Get-File "$NgrokBase/ngrok-v3-stable-windows-$arch.zip" $zip
  Expand-Archive -Path $zip -DestinationPath $tools -Force
  Remove-Item -Force $zip
  if ($NgrokToken) {
    try { & (Join-Path $tools 'ngrok.exe') config add-authtoken $NgrokToken --config (Join-Path $tools 'ngrok.yml') | Out-Null; Ok 'ngrok authtoken saved' }
    catch { Warn 'Could not save the ngrok authtoken.' }
  }
  Write-Text (Join-Path $InstallDir 'start-tunnel.bat') @"
@echo off
rem ngrok TCP tunnel. Friends connect to the tcp://X.tcp.ngrok.io:NNNNN address
rem it shows (without "tcp://"). The address changes every restart on free plans.
title $($script:ServerName) - ngrok tunnel
cd /d "%~dp0"
tools\ngrok.exe tcp $Port --config tools\ngrok.yml
pause
"@
  Ok 'ngrok installed'
}

function Write-Launchers {
  $lines = @('@echo off', 'rem Starts the tunnel and server(s), each in its own window. Generated by mc-setup.ps1', 'cd /d "%~dp0"')
  if ($Tunnel -eq 'ngrok') { $lines += 'start "tunnel" cmd /c start-tunnel.bat'; $lines += 'timeout /t 3 /nobreak >nul' }
  if ($Setup -eq 'velocity') {
    $lines += 'start "backend" cmd /c backend\start.bat'
    $lines += 'timeout /t 5 /nobreak >nul'
    $lines += 'start "proxy" cmd /c proxy\start.bat'
  } else {
    $lines += 'start "server" cmd /c server\start.bat'
  }
  $lines += 'echo Started. Each part runs in its own window.'
  $lines += 'echo To stop: type "stop" in the server window (and "end" in the proxy window).'
  $lines += 'timeout /t 5 >nul'
  Write-Text (Join-Path $InstallDir 'start-all.bat') ($lines -join "`n")
}

function Add-Autostart {
  try {
    $startup = [Environment]::GetFolderPath('Startup')
    $safe = ($script:ServerName -replace '[\\/:*?"<>|]', '').Trim(); if (-not $safe) { $safe = 'Minecraft server' }
    Write-Text (Join-Path $startup "$safe.bat") "@echo off`ncd /d `"$InstallDir`"`ncall start-all.bat`n"
    Ok "Autostart added (starts when you log in to Windows). Remove: delete '$safe.bat' from $startup"
  } catch { Warn 'Could not add autostart.' }
}

# ===========================================================================
#  CUSTOMISATION  (asked before the summary; downloads only happen at install)
# ===========================================================================
$script:ViewDist = 10; $script:SimDist = 10; $script:LevelType = 'normal'; $script:LevelName = 'world'
$script:Pvp = $true; $script:CmdBlocks = $false; $script:AllowFlight = $false; $script:Hardcore = $false
$script:SpawnProt = 16; $script:AllowNether = $true; $script:GenStruct = $true
$script:SpawnAnimals = $true; $script:SpawnMonsters = $true; $script:SpawnNpcs = $true
$script:ForceGm = $false; $script:IdleTimeout = 0
$script:ResPackUrl = ''; $script:ResPackSha1 = ''; $script:ResPackReq = $false
$script:IconSrc = ''; $script:Loader = 'none'; $script:LoaderVer = ''
$script:AutoRestart = $false; $script:BackupScript = $false
$script:Bedrock = $false; $script:BedrockPort = 19132; $script:PublicAddrBe = ''
$script:ServerName = 'Minecraft Server'
$script:ModEntries = New-Object System.Collections.ArrayList
$script:ExtraProps = @(); $script:OpNames = @(); $script:WlNames = @()
$script:MrSeen = New-Object System.Collections.ArrayList
$Modrinth = 'https://api.modrinth.com/v2'

function Ask-Bool([string]$q, [bool]$cur) { return (Ask-YesNo $q $cur) }
function Ask-Num([string]$q, [int]$cur, [int]$min, [int]$max) {
  $v = Ask-Text $q "$cur"
  $n = 0
  if ([int]::TryParse($v, [ref]$n) -and $n -ge $min -and $n -le $max) { return $n }
  Warn (Lf 'Please enter a number from {0} to {1}. Kept: {2}' $min $max $cur)
  return $cur
}

# ---- Server name ---------------------------------------------------------------
function Customise-Name {
  $old = $script:ServerName
  $v = Ask-Text "Name of your server (e.g. Creeper Cove).`nUsed for window titles, the autostart entry, backups and, if you have not set one yourself, as the MOTD in the server list." $script:ServerName
  $v = ($v -replace '["|&^%<>]', '').Trim()
  if ($v) { $script:ServerName = $v }
  if ($script:Motd -eq 'A Minecraft Server' -or $script:Motd -eq $old) { $script:Motd = $script:ServerName }
}

# ---- MOTD / icon ------------------------------------------------------------
function Customise-Motd {
  $v = Ask-Text @'
Server list message (MOTD).

Colours: &0 black &1 dark blue &2 dark green &3 dark aqua &4 dark red &5 purple &6 gold
&7 gray &8 dark gray &9 blue &a green &b aqua &c red &d pink &e yellow &f white
Styles:  &l bold  &o italic  &n underline  &k scrambled  &r reset
Use \n for a second line.    Example: &6&lMy Server\n&7Welcome!
'@ $script:Motd
  $script:Motd = $v -replace '"', ''
}
function Customise-Icon {
  $v = Ask-Text "Server icon: path to an image (png/jpg/gif...) or an https:// link.`nIt is converted to 64x64 pixels automatically (centre-cropped to a square).`nLeave empty for no icon." $script:IconSrc
  $v = $v.Trim('"')
  if ($v -and $v -notmatch '^https?://' -and -not (Test-Path -LiteralPath $v -PathType Leaf)) { Warn (Lf 'File not found: {0}' $v); return }
  $script:IconSrc = $v
}
function Convert-Icon([string]$src, [string]$dest) {
  try {
    Add-Type -AssemblyName System.Drawing
    $tmp = $null
    if ($src -match '^https?://') { $tmp = [IO.Path]::GetTempFileName(); Invoke-WebRequest -Uri $src -OutFile $tmp -UserAgent $UA -UseBasicParsing; $src = $tmp }
    $img = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $src).Path)
    $side = [Math]::Min($img.Width, $img.Height)
    $sx = [int](($img.Width - $side) / 2); $sy = [int](($img.Height - $side) / 2)
    $bmp = New-Object System.Drawing.Bitmap 64, 64
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, 64, 64), $sx, $sy, $side, $side, [System.Drawing.GraphicsUnit]::Pixel)
    $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $img.Dispose()
    if ($tmp) { Remove-Item -Force $tmp -ErrorAction SilentlyContinue }
    Ok 'Server icon created (64x64)'
  } catch { Warn "Could not convert the icon ($($_.Exception.Message)). Put a 64x64 server-icon.png in the server folder yourself." }
}

# ---- Mods / plugins -------------------------------------------------------------
function Get-MrLoaders { if ($Software -eq 'paper') { return '["paper","spigot","bukkit"]' } else { return "[`"$($script:Loader)`"]" } }
function Search-Mr([string]$q) {
  $ptype = 'mod'   # Modrinth lists plugins as project_type 'mod' too
  $cats = (Get-MrLoaders | ConvertFrom-Json) | ForEach-Object { '"categories:' + $_ + '"' }
  $facets = '[["project_type:' + $ptype + '"],["versions:' + $McVersion + '"],[' + ($cats -join ',') + ']]'
  $u = "$Modrinth/search?query=$([uri]::EscapeDataString($q))&limit=10&facets=$([uri]::EscapeDataString($facets))"
  return Get-Json $u
}
function Add-MrProject([string]$id, [int]$depth = 0) {
  if ($script:MrSeen -contains $id) { return $true }
  [void]$script:MrSeen.Add($id)
  $u = "$Modrinth/project/$id/version?loaders=$([uri]::EscapeDataString((Get-MrLoaders)))&game_versions=$([uri]::EscapeDataString('["' + $McVersion + '"]'))"
  try { $vs = @(Get-Json $u) } catch { Warn (Lf "Modrinth lookup failed for '{0}'." $id); return $false }
  if ($vs.Count -eq 0 -and $Software -eq 'paper') {   # plugins often keep working on newer Minecraft: use the newest build
    try { $vs = @(Get-Json "$Modrinth/project/$id/version?loaders=$([uri]::EscapeDataString((Get-MrLoaders)))") } catch {}
    if ($vs.Count -gt 0) { Warn (Lf "'{0}' is not marked for {1} yet - added its newest version ({2}). It may still work." $id $McVersion (@($vs[0].game_versions)[-1])) }
  }
  if ($vs.Count -eq 0) { Warn (Lf "'{0}' has no download for {1} on this loader." $id $McVersion); return $false }
  $v = $vs[0]
  $f = $v.files | Where-Object { $_.primary } | Select-Object -First 1
  if (-not $f) { $f = $v.files[0] }
  [void]$script:ModEntries.Add([pscustomobject]@{ Url = $f.url; Name = $f.filename; Sha1 = $f.hashes.sha1 })
  if ($depth -lt 2) {
    foreach ($d in @($v.dependencies | Where-Object { $_.dependency_type -eq 'required' -and $_.project_id })) {
      [void](Add-MrProject $d.project_id ($depth + 1))
    }
  }
  return $true
}
function Resolve-Loader {   # sets $script:LoaderVer; returns $false when unsupported
  $script:LoaderVer = ''
  try {
    switch ($script:Loader) {
      'fabric' {
        $l = @(Get-Json "https://meta.fabricmc.net/v2/versions/loader/$McVersion" | Where-Object { $_.loader.stable })
        if ($l.Count) { $script:LoaderVer = $l[0].loader.version }
      }
      'forge' {
        if (Compare-Ver $McVersion '1.17') {
          $p = (Get-Json 'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json').promos
          $fv = $p."$McVersion-recommended"; if (-not $fv) { $fv = $p."$McVersion-latest" }
          if ($fv) { $script:LoaderVer = "$McVersion-$fv" }
        }
      }
      'neoforge' {
        $prefix = $McVersion; if ($prefix.StartsWith('1.')) { $prefix = $prefix.Substring(2) }
        if ($prefix -notmatch '\.') { $prefix = "$prefix.0" }
        $all = @((Get-Json 'https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge').versions |
                 Where-Object { $_.StartsWith("$prefix.") -and $_ -notmatch '-' })
        if ($all.Count) { $script:LoaderVer = ($all | Sort-Object { [version]$_ } | Select-Object -Last 1) }
      }
    }
  } catch {}
  return [bool]$script:LoaderVer
}
function Install-Loader([string]$dir) {
  switch ($script:Loader) {
    'fabric' {
      $iv = @(Get-Json 'https://meta.fabricmc.net/v2/versions/installer' | Where-Object { $_.stable })[0].version
      Get-File "https://meta.fabricmc.net/v2/versions/loader/$McVersion/$($script:LoaderVer)/$iv/server/jar" (Join-Path $dir 'fabric-server-launch.jar')
      $script:Launch = '-jar fabric-server-launch.jar --nogui'
    }
    default {
      if ($script:Loader -eq 'forge') { $url = "https://maven.minecraftforge.net/net/minecraftforge/forge/$($script:LoaderVer)/forge-$($script:LoaderVer)-installer.jar" }
      else { $url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$($script:LoaderVer)/neoforge-$($script:LoaderVer)-installer.jar" }
      Get-File $url (Join-Path $dir 'installer.jar')
      Info "Running the $($script:Loader) installer (downloads libraries, can take a few minutes) ..."
      Push-Location $dir
      try {
        $p = Start-Process -FilePath $JavaBin -ArgumentList '-jar', 'installer.jar', '--installServer' -WorkingDirectory $dir -Wait -PassThru -NoNewWindow -RedirectStandardOutput 'installer.log' -RedirectStandardError 'installer.err'
        if ($p.ExitCode -ne 0) { Die "$($script:Loader) installer failed - see $dir\installer.log" }
      } finally { Pop-Location }
      Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $dir 'installer.jar'), (Join-Path $dir 'installer.jar.log')
      $a = Get-ChildItem (Join-Path $dir 'libraries') -Recurse -Filter 'win_args.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
      if (-not $a) { Die "Could not find the $($script:Loader) launch arguments after install." }
      $rel = $a.FullName.Substring($dir.Length).TrimStart('\', '/')
      $script:Launch = "@$rel --nogui"
    }
  }
  Ok "$($script:Loader) $($script:LoaderVer) installed"
}
function Pick-Loader {
  if ($Setup -eq 'velocity') { Warn "Mod loaders can't be combined with the Velocity setup here. (Paper plugins can - choose PaperMC.)"; return $false }
  $c = Ask-Menu 'Vanilla has no mod support itself. Pick a mod loader (it replaces the plain Vanilla server):' @(
    @('fabric',   'Fabric - lightweight, huge mod library (recommended)'),
    @('neoforge', 'NeoForge - big content mods (1.20.2+)'),
    @('forge',    'Forge - classic loader (1.17+)'),
    @('none',     'Plain Vanilla, no mods')) 'fabric'
  if ($c -eq 'none') { $script:Loader = 'none'; $script:ModEntries.Clear(); $script:MrSeen.Clear(); return $false }
  $script:Loader = $c
  if (-not (Resolve-Loader)) {
    Warn (Lf "{0} has no server release for Minecraft {1}. Pick another loader or another Minecraft version." $c $McVersion)
    $script:Loader = 'none'; return $false
  }
  $script:ModEntries.Clear(); $script:MrSeen.Clear()
  if ($c -eq 'fabric') { [void](Add-MrProject 'fabric-api') }
  return $true
}
function Get-Catalog([string]$kind) {
  if ($kind -eq 'plugins') { $rows = @($PluginCatalog); $file = 'plugins.list' } else { $rows = @($ModCatalog); $file = 'mods.list' }
  foreach ($dir in @($PSScriptRoot, (Get-Location).Path)) {
    if (-not $dir) { continue }
    $f = Join-Path $dir $file
    if (Test-Path $f) { foreach ($l in (Get-Content $f)) { $l = ($l -split '#')[0]; if ($l -like '*|*') { $rows += $l.Trim() } } }
  }
  return $rows
}
# returns rows with a 4th field: ok = has a build for this Minecraft version, old = not updated yet.
# Entries for the wrong platform are dropped.
function Get-CatalogCompatible($rows) {
  $slugs = @($rows | ForEach-Object { ($_ -split '\|')[0] })
  if ($slugs.Count -eq 0) { return @() }
  $ids = '[' + (($slugs | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']'
  try { $projects = @(Get-Json "$Modrinth/projects?ids=$([uri]::EscapeDataString($ids))") } catch { return @($rows | ForEach-Object { "$_|ok" }) }
  $want = @(Get-MrLoaders | ConvertFrom-Json)
  $st = @{}
  foreach ($p in $projects) {
    if (@($p.loaders | Where-Object { $want -contains $_ }).Count -eq 0) { continue }
    if (@($p.game_versions) -contains $McVersion) { $st[$p.slug] = 'ok' } else { $st[$p.slug] = 'old' }
  }
  return @($rows | Where-Object { $st.ContainsKey((($_ -split '\|')[0])) } | ForEach-Object { "$_|$($st[(($_ -split '\|')[0])])" })
}
function Mods-Popular([string]$kind) {
  Info (Lf 'Checking which popular {0} work with Minecraft {1} ...' (L $kind) $McVersion)
  $rows = @(Get-CatalogCompatible (Get-Catalog $kind))
  $items = @(); $nold = 0
  foreach ($r in $rows) {
    $p = $r -split '\|'
    if ($script:MrSeen -contains $p[0]) { continue }
    $d = $p[2]
    if ($p[-1] -eq 'old') { $d += "  " + (Lf '[not updated for {0} yet - newest version will be tried]' $McVersion); $nold++ }
    $items += ,@($p[0], "$($p[1]) - $d")
  }
  if ($items.Count -eq 0) { Say (L 'You already added everything in the popular list. Try the search option for more.'); Bar-Line; return }
  if ($nold -gt 0) { Say (Lf 'Minecraft {0} is very new, so {1} plugin(s) are marked as not updated yet. They often still work; pick them if you want to try.' $McVersion $nold); Bar-Line }
  $picked = @(Ask-Multi (Lf 'Pick the {0} you want (Space = tick, Enter = done, A = all)' (L $kind)) $items)
  foreach ($slug in $picked) { if (Add-MrProject $slug) { Ok (Lf 'Added {0}' $slug) } }
}
function Customise-Mods {
  $kind = 'plugins'
  if ($Software -eq 'vanilla') {
    $kind = 'mods'
    if ($script:Loader -eq 'none') { if (-not (Pick-Loader)) { return } }
  }
  while ($true) {
    $kw = L $kind
    if ($script:Loader -ne 'none') { $hdr = Lf 'Add {0}  ({1} queued, loader: {2})' $kw $script:ModEntries.Count "$($script:Loader) $($script:LoaderVer)" }
    else { $hdr = Lf 'Add {0}  ({1} queued)' $kw $script:ModEntries.Count }
    $c = Ask-Menu $hdr @(
      @('popular', (Lf 'Pick from a list of popular {0}' $kw)),
      @('search', (Lf 'Search Modrinth for {0} (compatible with {1})' $kw $McVersion)),
      @('url',    'Add direct https:// links to .jar files'),
      @('list',   (Lf 'Show / remove queued {0}' $kw)),
      @('back',   (Lf 'Done with {0}' $kw))) 'popular'
    switch ($c) {
      'back' { return }
      'popular' { Mods-Popular $kind }
      'search' {
        $q = Ask-Text (Lf 'Search Modrinth ({0} for Minecraft {1}). Examples: worldedit, essentialsx, lithium, luckperms' $kw $McVersion) ''
        if (-not $q) { continue }
        try { $res = Search-Mr $q } catch { Warn 'Modrinth search failed.'; continue }
        $hits = @($res.hits)
        if ($hits.Count -eq 0) { Warn (Lf "Nothing found for '{0}' that works with Minecraft {1}." $q $McVersion); continue }
        $opts = @()
        foreach ($h in $hits) {
          $d = "$($h.description)"; if ($d.Length -gt 38) { $d = $d.Substring(0, 38) }
          $t = "$($h.title)"; if ($t.Length -gt 22) { $t = $t.Substring(0, 22) }
          $opts += ,@($h.slug, "$t - $d")
        }
        $opts += ,@('cancel', 'Back')
        $pick = Ask-Menu (Lf "Results for '{0}':" $q) $opts $opts[0][0]
        if ($pick -ne 'cancel') { if (Add-MrProject $pick) { Ok (Lf "Added '{0}' (and any required dependencies)." $pick) } }
      }
      'url' {
        $q = Ask-Text "Direct https:// links to .jar files, separated by spaces.`nOnly use links from sources you trust - these files run on your server." ''
        foreach ($e in ($q -split '\s+' | Where-Object { $_ })) {
          if ($e -notmatch '^https://') { Warn (Lf "Skipping '{0}' (must start with https://)" $e); continue }
          $n = ($e -split '\?')[0].Split('/')[-1]
          if (-not $n.EndsWith('.jar')) { $n = "download-$(Get-Random).jar" }
          [void]$script:ModEntries.Add([pscustomobject]@{ Url = $e; Name = $n; Sha1 = '' })
        }
      }
      'list' {
        if ($script:ModEntries.Count -eq 0) { Warn 'Nothing queued yet.'; continue }
        $opts = @(); for ($i = 0; $i -lt $script:ModEntries.Count; $i++) { $opts += ,@("$i", $script:ModEntries[$i].Name) }
        $opts += ,@('cancel', 'Back (keep everything)')
        $pick = Ask-Menu 'Pick one to REMOVE from the install list:' $opts 'cancel'
        if ($pick -ne 'cancel') { $script:ModEntries.RemoveAt([int]$pick) }
      }
    }
  }
}

# ---- Whitelist / ops ---------------------------------------------------------------
function Parse-Names([string]$s) {
  $out = @()
  foreach ($n in ($s -split '[\s,]+' | Where-Object { $_ })) {
    if ($n -match '^[A-Za-z0-9_.]{3,16}$') { $out += $n } else { Warn (Lf "Skipping invalid name '{0}'" $n) }
  }
  return $out
}
function Customise-Players {
  $v = Ask-Text "Operators (admins). Minecraft usernames separated by spaces or commas.`nOps can use all commands." ($script:OpNames -join ' ')
  $script:OpNames = @(Parse-Names $v)
  $v = Ask-Text "Whitelist: only these players may join. Usernames separated by spaces or commas.`nLeave empty to keep the whitelist as chosen earlier." ($script:WlNames -join ' ')
  $script:WlNames = @(Parse-Names $v)
  if ($script:WlNames.Count) { $script:Whitelist = $true }
}
function Get-OfflineUuid([string]$name) {
  $md5 = [Security.Cryptography.MD5]::Create()
  $b = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("OfflinePlayer:$name"))
  $b[6] = ($b[6] -band 0x0f) -bor 0x30
  $b[8] = ($b[8] -band 0x3f) -bor 0x80
  return (($b | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Get-PlayerUuid([string]$name) {
  $id = $null
  if ($Online) {
    try { $id = (Invoke-RestMethod -Uri "https://api.mojang.com/users/profiles/minecraft/$name" -UserAgent $UA -UseBasicParsing -TimeoutSec 10).id } catch {}
  } else { $id = Get-OfflineUuid $name }
  if (-not $id) { return $null }
  return ('{0}-{1}-{2}-{3}-{4}' -f $id.Substring(0, 8), $id.Substring(8, 4), $id.Substring(12, 4), $id.Substring(16, 4), $id.Substring(20, 12))
}
function Write-PlayerLists([string]$dir) {
  $wl = @(); $ops = @()
  foreach ($n in $script:WlNames) {
    $u = Get-PlayerUuid $n
    if ($u) { $wl += [ordered]@{ uuid = $u; name = $n } } else { Warn (Lf "Could not look up '{0}' - add later with: whitelist add {0}" $n) }
  }
  foreach ($n in $script:OpNames) {
    $u = Get-PlayerUuid $n
    if ($u) { $ops += [ordered]@{ uuid = $u; name = $n; level = 4; bypassesPlayerLimit = $false } } else { Warn (Lf "Could not look up '{0}' - add later with: op {0}" $n) }
  }
  if ($script:WlNames.Count) { Write-Unix (Join-Path $dir 'whitelist.json') ((ConvertTo-Json -InputObject @($wl) -Depth 4) + "`n") }
  if ($script:OpNames.Count) { Write-Unix (Join-Path $dir 'ops.json') ((ConvertTo-Json -InputObject @($ops) -Depth 4) + "`n") }
}

# ---- World / gameplay / performance / extras -------------------------------------------
function Customise-World {
  $script:LevelType = Ask-Menu 'World type:' @(@('normal', 'Normal terrain'), @('flat', 'Superflat'), @('large_biomes', 'Large biomes'), @('amplified', 'Amplified (tall mountains)')) $script:LevelType
  $script:Seed = Ask-Text 'World seed (empty = random):' $script:Seed
  $n = Ask-Text 'World folder name:' $script:LevelName
  if ($n -match '^[A-Za-z0-9_.-]+$') { $script:LevelName = $n }
  $script:GenStruct   = Ask-Bool 'Generate structures (villages, strongholds, ...)?' $script:GenStruct
  $script:AllowNether = Ask-Bool 'Allow the Nether?' $script:AllowNether
  $script:Hardcore    = Ask-Bool 'Hardcore mode? (one life, forced hard difficulty)' $script:Hardcore
}
function Customise-Gameplay {
  $script:Pvp          = Ask-Bool 'Allow player-vs-player combat (PvP)?' $script:Pvp
  $script:CmdBlocks    = Ask-Bool 'Enable command blocks?' $script:CmdBlocks
  $script:AllowFlight  = Ask-Bool 'Allow flying (needed for some mods; otherwise flight is kicked)?' $script:AllowFlight
  $script:SpawnAnimals = Ask-Bool 'Spawn animals?' $script:SpawnAnimals
  $script:SpawnMonsters = Ask-Bool 'Spawn monsters?' $script:SpawnMonsters
  $script:SpawnNpcs    = Ask-Bool 'Spawn villagers?' $script:SpawnNpcs
  $script:ForceGm      = Ask-Bool 'Force everyone into the default game mode on every join?' $script:ForceGm
  $script:SpawnProt    = Ask-Num 'Spawn protection radius in blocks (0 = off):' $script:SpawnProt 0 200
  $script:IdleTimeout  = Ask-Num 'Kick idle players after N minutes (0 = never):' $script:IdleTimeout 0 1440
}
function Customise-Perf {
  $script:ViewDist = Ask-Num 'View distance in chunks (2-32). Lower = faster:' $script:ViewDist 2 32
  $script:SimDist  = Ask-Num 'Simulation distance in chunks (2-32). Lower = faster:' $script:SimDist 2 32
}
function Customise-Pack {
  $v = Ask-Text "Server resource pack: direct https:// link to a .zip (empty = none).`nPlayers are offered it when they join. Its checksum is calculated at install time." $script:ResPackUrl
  if ($v -and $v -notmatch '^https?://') { $kp = $script:ResPackUrl; if (-not $kp) { $kp = L 'none' }; Warn (Lf 'That is not a link. Kept: {0}' $kp); return }
  $script:ResPackUrl = $v
  if ($v) { $script:ResPackReq = Ask-Bool 'Kick players who decline the resource pack?' $script:ResPackReq }
}
function Customise-Extra {
  $v = Ask-Text "Any other server.properties setting as key=value, separated by spaces.`nExample: rcon.port=25575 enable-status=true network-compression-threshold=512" ($script:ExtraProps -join ' ')
  $script:ExtraProps = @()
  foreach ($kv in ($v -split '\s+' | Where-Object { $_ })) {
    if ($kv -match '^[a-z0-9.-]+=\S*$') { $script:ExtraProps += $kv } else { Warn (Lf "Skipping '{0}' (use key=value)" $kv) }
  }
}
function Customise-Maint {
  $script:AutoRestart  = Ask-Bool 'Restart the server automatically if it crashes?' $script:AutoRestart
  $script:BackupScript = Ask-Bool 'Create a backup script (zips the world into the backups folder, keeps the newest 10)?' $script:BackupScript
}

function Customise-Menu {
  $c = 'name'
  while ($true) {
    $icon = L 'none'; if ($script:IconSrc) { $icon = $script:IconSrc }
    $kindLbl = Lf 'Mods: {0} queued' $script:ModEntries.Count; if ($Software -eq 'paper') { $kindLbl = Lf 'Plugins: {0} queued' $script:ModEntries.Count }
    $pack = L 'none'; if ($script:ResPackUrl) { $pack = $script:ResPackUrl }
    $m = $script:Motd; if ($m.Length -gt 30) { $m = $m.Substring(0, 30) }
    $c = Ask-Menu "Customise your server. Pick a category; choose 'done' when finished." @(
      @('name',     (Lf 'Server name: {0}' $script:ServerName)),
      @('motd',     (Lf 'Server list message with colours: {0}' $m)),
      @('icon',     (Lf 'Server icon: {0}' $icon)),
      @('mods',     $kindLbl),
      @('players',  (Lf 'Operators ({0}) and whitelist ({1})' $script:OpNames.Count $script:WlNames.Count)),
      @('world',    'World type, seed, structures, nether, hardcore'),
      @('gameplay', 'PvP, command blocks, flying, mobs, spawn protection'),
      @('perf',     (Lf 'View / simulation distance: {0} / {1}' $script:ViewDist $script:SimDist)),
      @('pack',     (Lf 'Resource pack: {0}' $pack)),
      @('extra',    (Lf 'Any other server.properties setting ({0})' $script:ExtraProps.Count)),
      @('maint',    'Auto-restart on crash, backup script'),
      @('done',     'Finished customising')) $c
    switch ($c) {
      'name' { Customise-Name } 'motd' { Customise-Motd } 'icon' { Customise-Icon } 'mods' { Customise-Mods }
      'players' { Customise-Players } 'world' { Customise-World } 'gameplay' { Customise-Gameplay }
      'perf' { Customise-Perf } 'pack' { Customise-Pack } 'extra' { Customise-Extra }
      'maint' { Customise-Maint } 'done' { return }
    }
  }
}

function Write-BackupScripts([string]$srvDir) {
  $lv = $script:LevelName
  Write-Text (Join-Path $InstallDir 'backup.ps1') @"
# Zips the world into .\backups and keeps the newest 10. Best run while the server is stopped
# (or right after typing "save-all" in the server window) so the files are consistent.
`$ErrorActionPreference = 'Stop'
Set-Location `$PSScriptRoot
New-Item -ItemType Directory -Force -Path backups | Out-Null
`$tmp = Join-Path `$env:TEMP ('mc-backup-' + [guid]::NewGuid())
foreach (`$w in '$lv', '${lv}_nether', '${lv}_the_end') {
  `$src = Join-Path '$srvDir' `$w
  if (Test-Path `$src) { robocopy `$src (Join-Path `$tmp `$w) /E /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null }
}
if (Test-Path `$tmp) {
  `$zip = 'backups\world-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip'
  Compress-Archive -Path (Join-Path `$tmp '*') -DestinationPath `$zip
  Remove-Item -Recurse -Force `$tmp
  Write-Host "Backup done: `$zip"
} else { Write-Host 'No world folder found yet - start the server once first.' }
Get-ChildItem backups\world-*.zip | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force
"@
  Write-Text (Join-Path $InstallDir 'backup.bat') "@echo off`ncd /d `"%~dp0`"`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File backup.ps1`npause`n"
}


# ---------------------------------------------------------------------------
#  Where to put the server
# ---------------------------------------------------------------------------
function Get-FolderName([string]$n) {
  $n = ($n -replace '[\\/:*?"<>|]', '') -replace '\s+', '-'
  $n = $n.Trim('-', '.', ' ')
  if (-not $n) { $n = 'minecraft-server' }
  return $n
}
function Show-FolderDialog {   # returns a folder path, or '' if cancelled / not available
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Pick the folder to put your Minecraft server folder in'
    $d.ShowNewFolderButton = $true
    $top = New-Object System.Windows.Forms.Form; $top.TopMost = $true   # keeps the dialog in front of the console
    $r = $d.ShowDialog($top)
    if ($r -eq [System.Windows.Forms.DialogResult]::OK) { return $d.SelectedPath }
  } catch {}
  return ''
}
function Choose-InstallDir {   # sets $script:InstallDir
  $here = $PSScriptRoot; if (-not $here) { $here = (Get-Location).Path }
  $desk = [Environment]::GetFolderPath('Desktop'); if (-not $desk) { $desk = Join-Path $env:USERPROFILE 'Desktop' }
  $docs = [Environment]::GetFolderPath('MyDocuments'); if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }
  $fname = Get-FolderName $script:ServerName
  while ($true) {
    $c = Ask-Menu "Where should your server be saved? A new folder with your server's name is created there." @(
      @('here',      "$(L 'Next to this script (recommended)' -NoWrap)  -  $here"),
      @('desktop',   'On my Desktop'),
      @('documents', 'In my Documents folder'),
      @('other',     'Somewhere else (browse or type a folder)')) 'here'
    switch ($c) {
      'here'      { $base = $here }
      'desktop'   { $base = $desk }
      'documents' { $base = $docs }
      'other' {
        $base = ''
        if ($script:Fancy) { Say 'A folder window is opening - it may be behind this one.'; $base = Show-FolderDialog }
        if (-not $base) { $base = (Ask-Text 'Type the folder to put it in (it is created if it does not exist). Example: D:\Games' $env:USERPROFILE).Trim('"') }
      }
    }
    try {
      if (-not (Test-Path $base)) { New-Item -ItemType Directory -Force -Path $base | Out-Null }
      $base = (Resolve-Path $base).Path
    } catch { Warn "Cannot use $base. Please pick another place."; continue }
    $full = Join-Path $base $fname
    if ((Test-Path $full) -and (Get-ChildItem $full -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
      $again = Ask-Menu "A folder already exists at $full and is not empty. If it holds a server, its worlds are kept but start files and settings are replaced." @(
        @('other',    'Pick another place'),
        @('continue', 'Use it anyway')) 'other'
      if ($again -eq 'other') { continue }
    } else {
      $again = Ask-Menu "Your server will be installed in:`n$full" @(
        @('ok',    'Yes, use this folder'),
        @('other', 'No, pick another place')) 'ok'
      if ($again -eq 'other') { continue }
    }
    $script:InstallDir = $full; return
  }
}

# ===========================================================================
#  Customise an existing server (mc-customize.bat runs this: mc-setup.ps1 -Customize)
# ===========================================================================
$script:PropMap = [ordered]@{
  MaxPlayers = 'max-players'; Gamemode = 'gamemode'; ForceGm = 'force-gamemode'; Difficulty = 'difficulty'; Hardcore = 'hardcore'
  Pvp = 'pvp'; ViewDist = 'view-distance'; SimDist = 'simulation-distance'; SpawnProt = 'spawn-protection'
  CmdBlocks = 'enable-command-block'; AllowFlight = 'allow-flight'; AllowNether = 'allow-nether'; GenStruct = 'generate-structures'
  SpawnAnimals = 'spawn-animals'; SpawnMonsters = 'spawn-monsters'; SpawnNpcs = 'spawn-npcs'; IdleTimeout = 'player-idle-timeout'
  LevelName = 'level-name'; Seed = 'level-seed'; ResPackUrl = 'resource-pack'; ResPackSha1 = 'resource-pack-sha1'; ResPackReq = 'require-resource-pack'
}
function Get-Prop([string]$f, [string]$k) {
  if (-not (Test-Path $f)) { return $null }
  foreach ($l in (Get-Content $f -Encoding UTF8)) { if ($l.StartsWith("$k=")) { return $l.Substring($k.Length + 1) } }
  return $null
}
function Set-Props([string]$f, $kv) {   # $kv: ordered key -> value; every other line stays as it is
  if (-not (Test-Path $f)) { return }
  $lines = @(Get-Content $f -Encoding UTF8)
  foreach ($k in $kv.Keys) {
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith("$k=")) { $lines[$i] = "$k=$($kv[$k])"; $done = $true; break } }
    if (-not $done) { $lines += "$k=$($kv[$k])" }
  }
  Write-Unix $f (($lines -join "`n") + "`n")
}
function Load-Props([string]$dir) {
  $f = Join-Path $dir 'server.properties'
  if (-not (Test-Path $f)) { return }
  foreach ($n in $script:PropMap.Keys) {
    $v = Get-Prop $f $script:PropMap[$n]
    if ($null -eq $v) { continue }
    $cur = Get-Variable -Scope Script -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($cur -is [bool]) { Set-Variable -Scope Script -Name $n -Value ($v -eq 'true') }
    elseif ($cur -is [int]) { $i = 0; if ([int]::TryParse($v, [ref]$i)) { Set-Variable -Scope Script -Name $n -Value $i } }
    else { Set-Variable -Scope Script -Name $n -Value $v }
  }
  $v = Get-Prop $f 'level-type'; if ($v) { $script:LevelType = ($v -replace '\\', '') -replace '^minecraft:', '' }
  $v = Get-Prop $f 'motd'; if ($v) { $script:Motd = $v -replace '\\u00[aA]7', '&' }
  $v = Get-Prop $f 'white-list'; $script:Whitelist = ($v -eq 'true')
}
function Save-Props([string]$dir) {
  $kv = [ordered]@{}
  foreach ($n in $script:PropMap.Keys) {
    $cur = Get-Variable -Scope Script -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $cur) { continue }
    if ($cur -is [bool]) { $cur = $cur.ToString().ToLower() }
    $kv[$script:PropMap[$n]] = "$cur"
  }
  $kv['motd'] = ConvertTo-MotdProps $script:Motd
  $kv['level-type'] = "minecraft\:$($script:LevelType)"
  $w = $script:Whitelist.ToString().ToLower(); $kv['white-list'] = $w; $kv['enforce-whitelist'] = $w
  foreach ($e in $script:ExtraProps) { $kv[$e.Split('=')[0]] = $e.Substring($e.IndexOf('=') + 1) }
  Set-Props (Join-Path $dir 'server.properties') $kv
}
function Set-Conf([string]$k, [string]$v) {
  $f = Join-Path $script:InstallDir 'mc-setup.conf'
  $keep = @(); if (Test-Path $f) { $keep = @(Get-Content $f | Where-Object { -not $_.StartsWith("$k=") }) }
  $keep += "$k=$v"
  Write-Text $f ($keep -join "`n")
}
function Backup-Server([string]$label) {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $bd = Join-Path $script:InstallDir 'backups'; New-Item -ItemType Directory -Force -Path $bd | Out-Null
  $dest = Join-Path $bd "$label-$ts.zip"
  Info 'Making a backup first ...'
  try {
    Compress-Archive -Path $script:SrvDir -DestinationPath $dest -CompressionLevel Fastest -ErrorAction Stop
    Ok (Lf 'Backup saved: {0}' $dest); return $true
  } catch { Warn 'The backup failed - stopping here so nothing is lost.'; return $false }
}
function Rewrite-Start {   # rebuild start.bat for the current software/version/RAM
  $bat = Join-Path $script:SrvDir 'start.bat'
  $launch = '-jar server.jar --nogui'
  if (Test-Path $bat) { foreach ($l in (Get-Content $bat)) { if ($l -match '\s(-jar \S+ --nogui|@\S+ --nogui)\s*$') { $launch = $Matches[1] } } }
  if ($script:Launch -and $script:Loader -ne 'none') { $launch = $script:Launch }
  if ($script:Loader -ne 'none') { $flags = '-XX:+UseG1GC'; $xms = [int]($script:RamMb / 2) }
  elseif ($script:Software -eq 'paper') {
    $flags = "$AikarFlags -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"
    $xms = $script:RamMb; if ($script:RamMb -lt 2048) { $xms = [int]($script:RamMb / 2) }
  } else { $flags = '-XX:+UseG1GC'; $xms = [int]($script:RamMb / 2) }
  $role = 'server'; if ($script:Setup -eq 'velocity') { $role = 'backend' }
  Write-StartBat $script:SrvDir $script:JavaBin $script:RamMb $xms $flags $launch "$($script:ServerName) - $role"
}
function Find-Servers {
  $roots = @($PSScriptRoot, (Get-Location).Path, [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), $env:USERPROFILE) | Where-Object { $_ }
  $seen = @{}
  foreach ($r in $roots) {
    foreach ($f in @(Get-ChildItem -Path $r -Filter 'mc-setup.conf' -Recurse -Depth 2 -ErrorAction SilentlyContinue)) {
      $d = $f.DirectoryName; if (-not $seen.ContainsKey($d)) { $seen[$d] = $true; $d }
    }
  }
}
function Select-Server([string]$given) {   # sets $script:InstallDir
  if ($given) { $script:InstallDir = $given.Trim('"'); return }
  $found = @(Find-Servers)
  $opts = @()
  foreach ($d in $found) {
    $nm = ''; foreach ($l in (Get-Content (Join-Path $d 'mc-setup.conf'))) { if ($l -match '^SERVER_NAME=(.*)') { $nm = $Matches[1] } }
    $opts += ,@($d, "$nm   $d")
  }
  $opts += ,@('other', 'Pick another folder ...')
  $c = Ask-Menu 'Which server do you want to change?' $opts $opts[0][0]
  if ($c -eq 'other') {
    $c = ''
    if ($script:Fancy) { Say 'A folder window is opening - it may be behind this one.'; $c = Show-FolderDialog }
    if (-not $c) { $c = (Ask-Text 'Type the folder of your server (the one that contains start-all):' '').Trim('"') }
  }
  if (-not ((Test-Path (Join-Path $c 'mc-setup.conf')) -or (Test-Path (Join-Path $c 'server')))) { Die 'That folder does not look like a server made by this tool.' }
  $script:InstallDir = $c
}
function Load-Server {
  $c = Join-Path $script:InstallDir 'mc-setup.conf'
  $script:MaxPlayers = 20; $script:Gamemode = 'survival'; $script:Difficulty = 'normal'; $script:Seed = ''; $script:Whitelist = $false
  $script:Software = 'paper'; $script:Setup = 'standalone'; $script:Port = 25565; $script:RamMb = 2048; $script:McVersion = ''
  $script:JavaBin = ''; $script:Launch = ''
  if (Test-Path $c) {
    foreach ($l in (Get-Content $c)) {
      if ($l -notmatch '^([A-Z_]+)=(.*)$') { continue }
      $k = $Matches[1]; $v = $Matches[2]
      switch ($k) {
        'SERVER_NAME' { $script:ServerName = $v } 'SOFTWARE' { $script:Software = $v } 'LOADER' { $script:Loader = $v }
        'MC_VERSION' { $script:McVersion = $v } 'SETUP' { $script:Setup = $v } 'RAM_MB' { $script:RamMb = [int]$v }
        'PORT' { $script:Port = [int]$v } 'JAVA_BIN' { $script:JavaBin = $v } 'TUNNEL' { $script:Tunnel = $v }
        'BEDROCK' { $script:Bedrock = ($v -eq 'true') } 'BEDROCK_PORT' { $script:BedrockPort = [int]$v }
        'PUBLIC_ADDRESS' { $script:PublicAddr = $v } 'PUBLIC_ADDRESS_BEDROCK' { $script:PublicAddrBe = $v }
      }
    }
  }
  $script:SrvDir = Join-Path $script:InstallDir 'server'; if ($script:Setup -eq 'velocity') { $script:SrvDir = Join-Path $script:InstallDir 'backend' }
  if (-not (Test-Path $script:SrvDir)) { Die "I can not find the server folder inside $($script:InstallDir)." }
  $script:ModDir = 'plugins'; if ($script:Loader -ne 'none') { $script:ModDir = 'mods' }
  if (-not (Test-Path $script:JavaBin)) { $j = Get-Command java -ErrorAction SilentlyContinue; if ($j) { $script:JavaBin = $j.Source } }
  $bat = Join-Path $script:SrvDir 'start.bat'
  if ((Test-Path $bat) -and (Select-String -Path $bat -Pattern '^:again' -Quiet)) { $script:AutoRestart = $true }
  if (Test-Path (Join-Path $script:InstallDir 'backup.ps1')) { $script:BackupScript = $true }
  Load-Props $script:SrvDir
  $script:OpNames = @(); $script:WlNames = @()
  foreach ($pair in @(@('ops.json', 'OpNames'), @('whitelist.json', 'WlNames'))) {
    $jf = Join-Path $script:SrvDir $pair[0]
    if (Test-Path $jf) { try { Set-Variable -Scope Script -Name $pair[1] -Value @((Get-Content $jf -Raw | ConvertFrom-Json) | ForEach-Object { $_.name }) } catch {} }
  }
  $script:IconSrc = ''; $script:ModEntries = New-Object System.Collections.ArrayList; $script:MrSeen = New-Object System.Collections.ArrayList; $script:ExtraProps = @()
}
function Place-Queued {
  if ($script:ModEntries.Count -eq 0) { return }
  $md = Join-Path $script:SrvDir $script:ModDir; New-Item -ItemType Directory -Force -Path $md | Out-Null
  foreach ($e in $script:ModEntries) {
    $nm = Split-Path $e.Name -Leaf
    Get-File $e.Url (Join-Path $md $nm); Test-Hash (Join-Path $md $nm) 'SHA1' $e.Sha1
  }
  Ok (Lf '{0} file(s) placed in {1}' $script:ModEntries.Count $md)
  $script:ModEntries.Clear(); $script:MrSeen.Clear()
}
function Remove-Installed {
  $md = Join-Path $script:SrvDir $script:ModDir
  $jars = @(Get-ChildItem -Path $md -Filter '*.jar' -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($jars.Count -eq 0) { Say (L 'Nothing is installed in this folder yet.'); Bar-Line; return }
  $items = @(); foreach ($j in $jars) { $items += ,@($j.Name, $j.Name) }
  $picks = @(Ask-Multi 'Tick the ones to REMOVE (they are moved to a folder called removed, not deleted)' $items)
  $rd = Join-Path $md 'removed'; New-Item -ItemType Directory -Force -Path $rd | Out-Null
  foreach ($p in $picks) { Move-Item -Force -LiteralPath (Join-Path $md $p) $rd; Ok (Lf 'Removed {0}' $p) }
}
function Customise-Version {
  Info 'Fetching version list ...'
  if ($script:Software -eq 'paper' -and $script:Loader -eq 'none') { $list = @(Get-PaperVersions) } else { $list = @(Get-VanillaVersions) }
  if ($list.Count -eq 0) { Warn 'Could not get the version list (is the internet working?).'; return }
  $new = Select-Version 'Minecraft' $list
  if ($new -eq $script:McVersion) { Say (L 'That is the version you already have.'); Bar-Line; return }
  if (-not (Ask-YesNo (Lf "Change Minecraft from {0} to {1}?`n`nWorlds can not go back to an older version, so a full backup is made first. Plugins and mods may need updating afterwards." $script:McVersion $new) $false)) { return }
  if (-not (Backup-Server "before-$new")) { return }
  $old = $script:McVersion; $script:McVersion = $new
  $script:JavaBin = Ensure-Java (Get-JavaForMc $new)
  if ($script:Loader -ne 'none') {
    if (-not (Resolve-Loader)) { Warn 'This loader has no release for that version.'; $script:McVersion = $old; return }
    Install-Loader $script:SrvDir
  } elseif ($script:Software -eq 'paper') { Get-PaperMC 'paper' $new (Join-Path $script:SrvDir 'server.jar') }
  else { Get-Vanilla $new (Join-Path $script:SrvDir 'server.jar') }
  Rewrite-Start
  Set-Conf 'MC_VERSION' $new; Set-Conf 'JAVA_BIN' $script:JavaBin
  Ok (Lf 'Now on Minecraft {0}' $new)
  Say (L 'If a plugin or mod stops working with the new version, update or remove it from this menu. To go back, restore the backup from the backups folder.'); Bar-Line
}
function Customise-Bedrock {
  $pd = Join-Path $script:SrvDir 'plugins'; $rd = Join-Path $pd 'removed'
  if ($script:Bedrock) {
    if (-not (Ask-YesNo 'Bedrock support is ON. Turn it off? (Geyser and Floodgate are moved to a folder called removed.)' $false)) { return }
    New-Item -ItemType Directory -Force -Path $rd | Out-Null
    foreach ($j in 'Geyser-Spigot.jar', 'floodgate-spigot.jar') { if (Test-Path (Join-Path $pd $j)) { Move-Item -Force (Join-Path $pd $j) $rd } }
    $script:Bedrock = $false; Set-Conf 'BEDROCK' 'false'; Ok 'Bedrock support turned off.'; return
  }
  if ($script:Setup -eq 'velocity' -or $script:Loader -ne 'none') { Say (L 'Bedrock support here needs a plain PaperMC server (not Velocity, Fabric or Forge).'); Bar-Line; return }
  if (-not (Ask-YesNo (Lf "Let Bedrock players (phones, consoles, Windows 10/11) join too?`n`nGeyser and Floodgate are added. They need PaperMC. Bedrock names get a dot in front (for example .Steve). UDP port {0} is used." $script:BedrockPort) $true)) { return }
  if ($script:Software -ne 'paper') {
    if (-not (Ask-YesNo 'Your server is Vanilla. Switch it to PaperMC (same version, same world)? A full backup is made first.' $true)) { return }
    if (-not (Backup-Server 'before-paper')) { return }
    $script:JavaBin = Ensure-Java (Get-JavaForMc $script:McVersion)
    try { Get-PaperMC 'paper' $script:McVersion (Join-Path $script:SrvDir 'server.jar') } catch { Warn 'PaperMC has no build for this version.'; return }
    $script:Software = 'paper'; Set-Conf 'SOFTWARE' 'paper'; Rewrite-Start
  }
  $script:Bedrock = $true; Install-Geyser $script:SrvDir; Set-Conf 'BEDROCK' 'true'; Set-Conf 'BEDROCK_PORT' "$($script:BedrockPort)"
  Open-Firewall $script:BedrockPort 'UDP'
  Say (Lf 'Bedrock players need UDP port {0} reachable. With playit.gg run  powershell -File mc-setup.ps1 -TunnelGuide  to add the Bedrock tunnel; with a router, forward UDP {0} too.' $script:BedrockPort); Bar-Line
}
function Invoke-CustomiseExisting([string]$given) {
  Select-Server $given; Load-Server
  Say (L 'Tip: stop the server first (type  stop  in its window). Changes are read when it starts.'); Bar-Line
  $c = 'name'
  while ($true) {
    $m = $script:Motd; if ($m.Length -gt 30) { $m = $m.Substring(0, 30) }
    $pk = L 'none'; if ($script:ResPackUrl) { $pk = $script:ResPackUrl }
    if ($script:Software -eq 'paper') { $addL = L 'Add plugins'; $remL = L 'Remove plugins' } else { $addL = L 'Add mods'; $remL = L 'Remove mods' }
    if ($script:Bedrock) { $beL = L 'Bedrock players: ON (Geyser + Floodgate)' } else { $beL = L 'Bedrock players: off' }
    $c = Ask-Menu 'What do you want to change?' @(
      @('name',     (Lf 'Server name: {0}' $script:ServerName)),
      @('motd',     (Lf 'Server list message with colours: {0}' $m)),
      @('icon',     'Server icon'),
      @('mods',     $addL),
      @('remove',   $remL),
      @('players',  (Lf 'Operators ({0}) and whitelist ({1})' $script:OpNames.Count $script:WlNames.Count)),
      @('world',    'World type, seed, structures, nether, hardcore'),
      @('gameplay', 'PvP, command blocks, flying, mobs, spawn protection'),
      @('perf',     (Lf 'View / simulation distance: {0} / {1}' $script:ViewDist $script:SimDist)),
      @('pack',     (Lf 'Resource pack: {0}' $pk)),
      @('extra',    'Any other server.properties setting'),
      @('maint',    'Auto-restart on crash, backup script'),
      @('version',  (Lf 'Change the Minecraft version (now {0})' $script:McVersion)),
      @('bedrock',  $beL),
      @('backup',   'Make a backup now'),
      @('done',     'Finished customising')) $c
    switch ($c) {
      'name' { Customise-Name; Set-Conf 'SERVER_NAME' $script:ServerName; Save-Props $script:SrvDir }
      'motd' { Customise-Motd; Save-Props $script:SrvDir }
      'icon' {
        Customise-Icon
        if ($script:IconSrc) {
          $idir = $script:SrvDir; if ($script:Setup -eq 'velocity') { $idir = Join-Path $script:InstallDir 'proxy' }
          try { Convert-Icon $script:IconSrc (Join-Path $idir 'server-icon.png') } catch { Warn "Could not convert the icon ($($_.Exception.Message)). Put a 64x64 server-icon.png in the server folder yourself." }
        }
      }
      'mods' { Customise-Mods; Place-Queued }
      'remove' { Remove-Installed }
      'players' {
        Customise-Players
        if ($script:WlNames.Count) { $script:Whitelist = $true }
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $script:SrvDir 'ops.json'), (Join-Path $script:SrvDir 'whitelist.json')
        Write-PlayerLists $script:SrvDir; Save-Props $script:SrvDir
      }
      'world' {
        Customise-World; Save-Props $script:SrvDir
        Say (L 'Changing the seed, world type or world folder name only affects a NEW world. Your current world stays as it is.'); Bar-Line
      }
      'gameplay' { Customise-Gameplay; Save-Props $script:SrvDir }
      'perf' { Customise-Perf; Save-Props $script:SrvDir }
      'pack' {
        Customise-Pack
        if ($script:ResPackUrl) {
          $tmp = [IO.Path]::GetTempFileName()
          try { Invoke-WebRequest -Uri $script:ResPackUrl -OutFile $tmp -UserAgent $UA -UseBasicParsing; $script:ResPackSha1 = (Get-FileHash -Algorithm SHA1 $tmp).Hash.ToLower() }
          catch { Warn 'Could not download the resource pack - skipping it.'; $script:ResPackUrl = ''; $script:ResPackSha1 = '' }
          Remove-Item -Force -ErrorAction SilentlyContinue $tmp
        } else { $script:ResPackSha1 = '' }
        Save-Props $script:SrvDir
      }
      'extra' { Customise-Extra; Save-Props $script:SrvDir }
      'maint' {
        Customise-Maint; Rewrite-Start
        if ($script:BackupScript) { Write-BackupScripts $script:SrvDir } else { Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $script:InstallDir 'backup.ps1') }
      }
      'version' { Customise-Version }
      'bedrock' { Customise-Bedrock }
      'backup' { [void](Backup-Server 'manual') }
      'done' { Say (L 'All done. Start (or restart) your server to use the changes.'); Bar-Line; return }
    }
    Ok 'Saved.'
  }
}

function Ask-Bedrock([string]$mode) {   # sets $script:Bedrock (and switches to Paper when needed)
  $script:Bedrock = $false
  if ($script:Setup -eq 'velocity') { return }
  if ($mode -eq 'simple') {
    $q = "Should Bedrock players (phones, consoles, Windows 10/11) be able to join too?`n`nThey join through a free add-on called Geyser, so they do not need a Java account. It needs the Standard (Paper) server, which is chosen for you. Bedrock names get a dot in front (for example .Steve)."
  } else {
    $q = "Also let Bedrock players join (Geyser + Floodgate)?`n`nBedrock Edition (phones, consoles, Windows 10/11) players can then join without a Java account. It needs PaperMC and opens UDP port 19132. Bedrock player names get a dot in front (for example .Steve)."
  }
  if (Ask-YesNo $q $false) {
    $script:Bedrock = $true
    if ($script:Software -ne 'paper') { $script:Software = 'paper'; Say (L 'Switched to the Standard (PaperMC) server, because Bedrock support needs it.'); Bar-Line }
  }
}

function Invoke-SimpleSetup {
  $n = (Ask-Text 'What do you want to call your server?' 'My Minecraft Server') -replace '["|&^%<>]', ''
  if (-not $n.Trim()) { $n = 'My Minecraft Server' }
  $script:ServerName = $n.Trim(); $script:Motd = $script:ServerName
  Choose-InstallDir
  $script:Software = Ask-Menu 'Which kind of server do you want?' @(
    @('paper',   'Standard (recommended) - fast, and you can add plugins later'),
    @('vanilla', 'Pure Minecraft - exactly like the official game')) 'paper'
  Ask-Bedrock 'simple'
  $script:Net = Ask-Menu 'How will your friends join?' @(
    @('tunnel',  'Over the internet - easiest, no router settings (free)'),
    @('portfwd', 'Over the internet using my router (port forwarding)'),
    @('lan',     'Only people on my home Wi-Fi')) 'tunnel'
  $script:Online = Ask-YesNo "Does everyone who will join own Minecraft (a paid Microsoft account)?`n`nYES = safest, recommended.`nNO  = anyone can join with any name (only for friends you trust)." $true
  Info 'Finding the newest version ...'
  if ($script:Software -eq 'paper') { $v = @(Get-PaperVersions) } else { $v = @(Get-VanillaVersions) }
  if ($v.Count -eq 0) { Die 'Could not get the version list (is the internet working?).' }
  $script:McVersion = Select-Version 'Minecraft' $v
  $script:Setup = 'standalone'; $script:Whitelist = $false; $script:Port = 25565; $script:BackendPort = 25566
  $script:MaxPlayers = 20; $script:Gamemode = 'survival'; $script:Difficulty = 'normal'; $script:Seed = ''
  $script:Autostart = $false; $script:Tunnel = 'none'; $script:NgrokToken = ''; $script:DoUpnp = $false; $script:DoFirewall = $false
  $total = 4096
  try { $total = [int]((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1MB) } catch {}
  $script:RamMb = [int]([Math]::Floor($total / 2 / 1024) * 1024)
  if ($script:RamMb -gt 4096) { $script:RamMb = 4096 }
  if ($script:RamMb -lt 1024) { $script:RamMb = 1024 }
  switch ($script:Net) {
    'tunnel'  { $script:Tunnel = 'playit' }
    'portfwd' { $script:DoUpnp = $true; $script:DoFirewall = $true }
    'lan'     { $script:DoFirewall = $true }
  }
  if (Ask-YesNo "Want to change more things (server message, icon, mods, whitelist, world...)?`nMost people choose No - you can still do that later." $false) { Customise-Menu }
}

# ===========================================================================
#  THE WIZARD
# ===========================================================================
try {
  $Host.UI.RawUI.WindowTitle = 'Minecraft Server Setup'
} catch {}

try {
  Show-Banner
  Pick-Language
  Out-Raw "$cGr$($Sym.top)$cR  $cB$(L "Let's set up your Minecraft server")$cR`n"
  Say "$cD$(L 'Use the arrow keys and Enter. Press Ctrl+C at any time to quit.')$cR"
  Say "$cD$(L 'Nothing is installed until you confirm at the end.')$cR"
  Bar-Line
  if ($Customize) { Invoke-CustomiseExisting $Server; exit 0 }
  if ($TunnelGuide) {   # just the playit.gg guide, for a server that is already installed
    $Port = 25565; $conf = Join-Path $env:USERPROFILE 'minecraft-server\mc-setup.conf'
    $roots = @($PSScriptRoot, (Get-Location).Path, [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), $env:USERPROFILE) | Where-Object { $_ }
    foreach ($r in $roots) {   # find the newest server folder made by this script
      $f = Get-ChildItem -Path $r -Filter 'mc-setup.conf' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($f) { $conf = $f.FullName; break }
    }
    if (Test-Path $conf) {
      foreach ($l in (Get-Content $conf)) {
        if ($l -match '^PORT=(\d+)') { $Port = [int]$Matches[1] }
        if ($l -match '^PUBLIC_ADDRESS=(.+)') { $script:PublicAddr = $Matches[1] }
        if ($l -match '^PUBLIC_ADDRESS_BEDROCK=(.+)') { $script:PublicAddrBe = $Matches[1] }
        if ($l -match '^BEDROCK=true') { $script:Bedrock = $true }
        if ($l -match '^BEDROCK_PORT=(\d+)') { $script:BedrockPort = [int]$Matches[1] }
      }
    }
    Start-TunnelGuide
    if (Test-Path $conf) { $keep = @(Get-Content $conf | Where-Object { $_ -notmatch '^PUBLIC_ADDRESS' }); $keep += "PUBLIC_ADDRESS=$($script:PublicAddr)"; $keep += "PUBLIC_ADDRESS_BEDROCK=$($script:PublicAddrBe)"; Write-Text $conf ($keep -join "`n") }
    Out-Raw "$cG$($Sym.end)$cR  Done.`n"
    exit 0
  }
  $Mode = Ask-Menu 'How do you want to set up?' @(
    @('simple',   'Simple - a few easy questions, everything else is chosen for you'),
    @('advanced', 'Advanced - choose every option yourself')) 'simple'

  if ($Mode -eq 'simple') { Invoke-SimpleSetup } else {
  $n = (Ask-Text 'What do you want to call your server?' 'Minecraft Server') -replace '["|&^%<>]', ''
  if ($n.Trim()) { $script:ServerName = $n.Trim() }
  Choose-InstallDir
  $InstallDir = $script:InstallDir

  $Software = Ask-Menu 'Which server software?' @(
    @('paper',   'PaperMC - faster, supports plugins (recommended)'),
    @('vanilla', 'Vanilla - the official Mojang server, no plugins')) 'paper'

  $Setup = Ask-Menu "Normal server or Velocity proxy?  (Velocity sits in front of your server;`n  useful if you want to link several servers later)" @(
    @('standalone', 'Normal - one server, players connect directly'),
    @('velocity',   'Velocity proxy + Paper backend server')) 'standalone'

  if ($Setup -eq 'velocity' -and $Software -eq 'vanilla') {
    if (Ask-YesNo "Velocity needs a PaperMC backend (Vanilla can't receive the player info Velocity forwards).`nSwitch the backend to PaperMC?" $true) { $Software = 'paper' } else { $Setup = 'standalone' }
  }

  Ask-Bedrock 'advanced'
  if ($Setup -eq 'velocity') { $script:Bedrock = $false }

  Info 'Fetching version list ...'
  if ($Software -eq 'paper') { $McVersion = Select-Version 'Minecraft' (Get-PaperVersions) }
  else                       { $McVersion = Select-Version 'Minecraft' (Get-VanillaVersions) }

  $Online = Ask-YesNo @'
Player login: require premium (online mode)?

 YES (recommended): players must own Minecraft and log in with a Microsoft
     account. Skins work and nobody can join under someone else's name.
 NO  (offline / cracked mode): anyone can join with any username, no account
     check. Only for LAN or trusted friends - turn on the whitelist.
'@ $true

  $Whitelist = Ask-YesNo "Turn on the whitelist? Only players you add with 'whitelist add <name>' can join." (-not $Online)

  $TotalMb = 4096
  try { $TotalMb = [int]((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1MB) } catch {}
  $Suggest = [Math]::Min(8192, [Math]::Max(1024, [int]($TotalMb / 2)))
  $Suggest = [int]([Math]::Floor($Suggest / 1024) * 1024)
  $RamChoice = Ask-Menu "How much RAM for the Minecraft server? (this PC has $TotalMb MB)" @(
    @('1024', '1 GB  - tiny, 1-3 players'),
    @('2048', '2 GB  - small group'),
    @('4096', '4 GB  - recommended for most'),
    @('6144', '6 GB  - many players / big world'),
    @('8192', '8 GB  - large server'),
    @('custom', 'Type an amount in MB')) "$Suggest"
  if ($RamChoice -eq 'custom') { $RamChoice = Ask-Text 'RAM in MB (e.g. 3072):' "$Suggest" }
  $RamMb = 0
  if (-not [int]::TryParse($RamChoice, [ref]$RamMb)) { Die 'RAM must be a number of MB.' }
  if ($RamMb -gt $TotalMb - 512) { Warn "That is close to or more than all your RAM ($TotalMb MB)." }

  $Port = 0
  if (-not [int]::TryParse((Ask-Text 'Port players connect to:' '25565'), [ref]$Port) -or $Port -lt 1 -or $Port -gt 65535) { Die 'Invalid port.' }
  $BackendPort = 25566; if ($Port -eq 25566) { $BackendPort = 25567 }

  $Motd = (Ask-Text 'Server name / message shown in the server list (MOTD):' 'A Minecraft Server') -replace '"', ''
  $MaxPlayers = 20; [void][int]::TryParse((Ask-Text 'Maximum players:' '20'), [ref]$MaxPlayers)
  $Gamemode = Ask-Menu 'Default game mode:' @(@('survival', 'Survival'), @('creative', 'Creative'), @('adventure', 'Adventure'), @('spectator', 'Spectator')) 'survival'
  $Difficulty = Ask-Menu 'Difficulty:' @(@('peaceful', 'Peaceful'), @('easy', 'Easy'), @('normal', 'Normal'), @('hard', 'Hard')) 'normal'
  $Seed = Ask-Text 'World seed (leave empty for random):' ''

  $Net = Ask-Menu 'How will friends outside your home connect?' @(
    @('tunnel',  'Tunnel - easiest, no router changes needed'),
    @('portfwd', 'Port forwarding - open a port on your router'),
    @('lan',     'LAN only - just people on my Wi-Fi/network')) 'tunnel'

  $Tunnel = 'none'; $NgrokToken = ''; $DoUpnp = $false; $DoFirewall = $false
  switch ($Net) {
    'tunnel' {
      $Tunnel = Ask-Menu 'Which tunnel provider?' @(
        @('playit', 'playit.gg - free, made for games, no card (recommended)'),
        @('ngrok',  'ngrok - needs a free account; TCP needs card verification'),
        @('none',   "I'll set up a tunnel myself (e.g. Cloudflare, Tailscale)")) 'playit'
      if ($Tunnel -eq 'ngrok') {
        $NgrokToken = Ask-Text "Paste your ngrok authtoken (https://dashboard.ngrok.com/get-started/your-authtoken).`nLeave empty to add it later." '' -Secret
      }
    }
    'portfwd' {
      $DoUpnp = Ask-YesNo "Try to open the port on your router automatically with UPnP?`n(Works on many home routers. If it fails you get manual instructions.)" $true
      $DoFirewall = Ask-YesNo "Allow port $Port through Windows Firewall? (asks for admin permission)" $true
    }
    'lan' {
      $DoFirewall = Ask-YesNo "Allow port $Port through Windows Firewall? (asks for admin permission)" $true
    }
  }

  $Autostart = Ask-YesNo 'Start the server automatically when you log in to Windows?' $false

  if (Ask-YesNo "Customise more?`nColoured MOTD, server icon, mods or plugins, whitelist and operators, world type, PvP, command blocks, resource pack, view distance, auto-restart, backups and more.`nChoose No to keep sensible defaults." $true) { Customise-Menu }
  }   # end of advanced questions

  if (-not (Ask-YesNo "Minecraft EULA`nTo run a server you must agree to the Minecraft End User License Agreement:`nhttps://aka.ms/MinecraftEULA`n`nDo you agree to the EULA?" $false)) {
    Die 'You must accept the EULA to run a Minecraft server.'
  }

  $NetDesc = $Net
  if ($Net -eq 'tunnel')  { $NetDesc = "tunnel ($Tunnel)" }
  if ($Net -eq 'portfwd') { $NetDesc = "port forwarding (UPnP: $DoUpnp)" }
  $SetupDesc = $Setup; if ($Setup -eq 'velocity') { $SetupDesc = "velocity (proxy :$Port -> backend 127.0.0.1:$BackendPort)" }
  if ($Mode -eq 'simple') {
    $fr = 'home Wi-Fi only'; if ($Net -eq 'tunnel') { $fr = 'over the internet (free tunnel)' } elseif ($Net -eq 'portfwd') { $fr = 'over the internet (router port forwarding)' }
    $ty = 'Pure Minecraft'; if ($Software -eq 'paper') { $ty = 'Standard' }
    $ac = 'anyone can join with any name'; if ($Online) { $ac = 'everyone needs a Minecraft account' }
    $sumText = "$(L 'Name:')  $($script:ServerName)`n$(L 'Type:')  $(L $ty) (Minecraft $McVersion)`n$(L 'Friends:')  $(L $fr)`n$(L 'Accounts:')  $(L $ac)`n$(L 'Memory:')  $([int]($RamMb / 1024)) GB`n$(L 'Folder:')  $InstallDir"
    if ($script:Bedrock) { $sumText += "`n$(L 'Bedrock:')  $(L 'phones, consoles and Windows 10/11 can join too')" }
  } else {
    $icon = 'none'; if ($script:IconSrc) { $icon = $script:IconSrc }
    $sumText = @"
Folder:       $InstallDir
Software:     $Software $McVersion
Setup:        $SetupDesc
Premium:      $Online   Whitelist: $Whitelist
RAM:          $RamMb MB   Port: $Port
MOTD:         $Motd
Players:      max $MaxPlayers, $Gamemode, $Difficulty
Network:      $NetDesc
Autostart:    $Autostart
Bedrock:      $($script:Bedrock)
Name:         $($script:ServerName)
Extras:       icon: $icon, mods/plugins: $($script:ModEntries.Count), loader: $($script:Loader)
              ops: $($script:OpNames.Count), whitelist names: $($script:WlNames.Count), world: $($script:LevelType)
"@
  }
  Show-Box 'Summary' $sumText
  if (-not (Ask-YesNo 'Install now?' $true)) { Cancelled }

  # =========================================================================
  #  INSTALL
  # =========================================================================
  Header 'Installing your Minecraft server'
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

  Write-Step 'Step 1 of 4 - Checking Java'
  $ReqJava = Get-JavaForMc $McVersion
  Info "Minecraft $McVersion needs Java $ReqJava+"
  $JavaBin = Ensure-Java $ReqJava

  $SrvDir = Join-Path $InstallDir 'server'; if ($Setup -eq 'velocity') { $SrvDir = Join-Path $InstallDir 'backend' }
  New-Item -ItemType Directory -Force -Path $SrvDir | Out-Null
  Write-Step 'Step 2 of 4 - Downloading Minecraft (this can take a minute)'
  $script:Launch = '-jar server.jar --nogui'; $ModDir = 'plugins'

  if ($script:Loader -ne 'none') {
    Install-Loader $SrvDir; $ModDir = 'mods'
    $JvmFlags = '-XX:+UseG1GC'; $Xms = [int]($RamMb / 2)
  } elseif ($Software -eq 'paper') {
    Get-PaperMC 'paper' $McVersion (Join-Path $SrvDir 'server.jar')
    $JvmFlags = "$AikarFlags -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"
    $Xms = $RamMb; if ($RamMb -lt 2048) { $Xms = [int]($RamMb / 2) }
  } else {
    Get-Vanilla $McVersion (Join-Path $SrvDir 'server.jar')
    $JvmFlags = '-XX:+UseG1GC'
    $Xms = [int]($RamMb / 2)
  }

  if ($script:ResPackUrl) {
    Info 'Calculating the resource pack checksum ...'
    $tmpPack = [IO.Path]::GetTempFileName()
    try { Invoke-WebRequest -Uri $script:ResPackUrl -OutFile $tmpPack -UserAgent $UA -UseBasicParsing; $script:ResPackSha1 = (Get-FileHash -Algorithm SHA1 $tmpPack).Hash.ToLower() }
    catch { Warn 'Could not download the resource pack - skipping it.'; $script:ResPackUrl = '' }
    Remove-Item -Force -ErrorAction SilentlyContinue $tmpPack
  }

  if ($Setup -eq 'velocity') {
    # Backend: offline, localhost only - Velocity does the authentication
    Write-ServerProperties $SrvDir '127.0.0.1' $BackendPort $false
    Write-StartBat $SrvDir $JavaBin $RamMb $Xms $JvmFlags $script:Launch "$($script:ServerName) - backend"

    $ProxyDir = Join-Path $InstallDir 'proxy'
    New-Item -ItemType Directory -Force -Path $ProxyDir | Out-Null
    $VelVer = Get-VelocityLatest
    if (-not $VelVer) { Die 'Could not find a Velocity version.' }
    $ProxyJava = Ensure-Java ([Math]::Max($ReqJava, 21))
    Get-PaperMC 'velocity' $VelVer (Join-Path $ProxyDir 'velocity.jar')
    Set-VelocityConfig $ProxyDir $ProxyJava
    $secret = (Get-Content (Join-Path $ProxyDir 'forwarding.secret') -Raw).Trim()
    Set-PaperVelocity $SrvDir $secret
    Write-StartBat $ProxyDir $ProxyJava 512 512 '-XX:+UseG1GC -XX:G1HeapRegionSize=4M -XX:+UnlockExperimentalVMOptions -XX:+ParallelRefProcEnabled -XX:+AlwaysPreTouch -XX:MaxInlineLevel=15' '-jar velocity.jar' "$($script:ServerName) - proxy"
    $IconDir = $ProxyDir
  } else {
    Write-ServerProperties $SrvDir '' $Port $Online
    Write-StartBat $SrvDir $JavaBin $RamMb $Xms $JvmFlags $script:Launch "$($script:ServerName) - server"
    $IconDir = $SrvDir
  }
  Ok "Server files written to $SrvDir"

  if ($script:IconSrc) {
    try { Convert-Icon $script:IconSrc (Join-Path $IconDir 'server-icon.png') }
    catch { Warn "Could not convert the icon ($($_.Exception.Message)). Put a 64x64 server-icon.png in the server folder yourself." }
  }
  if ($script:ModEntries.Count) {
    $md = Join-Path $SrvDir $ModDir
    New-Item -ItemType Directory -Force -Path $md | Out-Null
    foreach ($e in $script:ModEntries) {
      $nm = Split-Path $e.Name -Leaf
      Get-File $e.Url (Join-Path $md $nm)
      Test-Hash (Join-Path $md $nm) 'SHA1' $e.Sha1
    }
    Ok "$($script:ModEntries.Count) file(s) placed in $md"
  }
  if ($script:Bedrock) { Install-Geyser $SrvDir }
  if ($script:WlNames.Count + $script:OpNames.Count) { Write-PlayerLists $SrvDir }
  if ($script:BackupScript) { Write-BackupScripts $SrvDir }

  Write-Step 'Step 3 of 4 - Setting up internet access'
  switch ($Tunnel) { 'playit' { Install-Playit } 'ngrok' { Install-Ngrok } }
  if ($DoFirewall) { Open-Firewall $Port }
  if ($DoFirewall -and $script:Bedrock) { Open-Firewall $script:BedrockPort 'UDP' }
  $UpnpOk = $false
  if ($DoUpnp) { $UpnpOk = Add-UPnP $Port }
  if ($DoUpnp -and $script:Bedrock) { if (-not (Add-UPnP $script:BedrockPort 'UDP')) { $UpnpOk = $false } }

  Write-Launchers
  if ($Tunnel -eq 'playit') {
    Write-Step 'playit.gg tunnel'
    if (Ask-YesNo 'Set up your free playit.gg tunnel now with a step-by-step guide? (about 10 minutes, you can also do it later)' $true) { Start-TunnelGuide }
  }
  Write-Step 'Step 4 of 4 - Finishing up'
  if ($Autostart) { Add-Autostart }

  Write-Text (Join-Path $InstallDir 'mc-setup.conf') @"
# Answers used by mc-setup.ps1 v$ScriptVersion on $(Get-Date)
SERVER_NAME=$($script:ServerName)
SOFTWARE=$Software
LOADER=$($script:Loader)
MC_VERSION=$McVersion
SETUP=$Setup
ONLINE=$Online
RAM_MB=$RamMb
PORT=$Port
NET=$Net
TUNNEL=$Tunnel
PUBLIC_ADDRESS=$($script:PublicAddr)
BEDROCK=$($script:Bedrock.ToString().ToLower())
BEDROCK_PORT=$($script:BedrockPort)
PUBLIC_ADDRESS_BEDROCK=$($script:PublicAddrBe)
JAVA_BIN=$JavaBin
"@

  # --- Final instructions --------------------------------------------------
  $Lan = Get-LanIp
  if ($Mode -eq 'simple') {
    $join = "$Lan`:$Port`n`n(Only on the same Wi-Fi.)"
    if ($Net -eq 'tunnel' -and $Tunnel -eq 'playit') {
      if ($script:PublicAddr) { $join = "$($script:PublicAddr)`n`n(Your playit.gg address. Keep playit running while you play.)" }
      else { $join = "(not set up yet)`nRun  powershell -File mc-setup.ps1 -TunnelGuide  for the step-by-step guide to get your address." }
    }
    elseif ($Net -eq 'tunnel') { $join = "shown in the tunnel window when you start the server." }
    elseif ($Net -eq 'portfwd') {
      $Pub = Get-PublicIp; $join = "${Pub}:$Port"
      if (-not $UpnpOk) { $join += "   (First open port $Port on your router and send it to $Lan - see README.)" }
    }
    $fin = "To start your server, run:`n>> $InstallDir\start-all.bat`n`nTo stop it, type  stop  in the server window.`n`nFriends join with:`n>> $join"
    if ($script:Bedrock) {
      $bj = "$Lan`:$($script:BedrockPort)"
      if ($Net -eq 'tunnel' -and $Tunnel -eq 'playit') { $bj = '(not set up yet)'; if ($script:PublicAddrBe) { $bj = $script:PublicAddrBe } }
      elseif ($Net -eq 'portfwd') { $bj = "${Pub}:$($script:BedrockPort)" }
      $fin += "`n`n$(L 'Bedrock players (phones, consoles, Windows 10/11) join with:')`n>> $bj`n$(L '(In Minecraft Bedrock: Play > Servers > Add Server. Their names get a dot in front, like .Steve.)')"
    }
    if (-not $Online) { $fin += "`n`nNote: anyone can join with any name. Only share the address with people you trust." }
    Show-Box 'Your server is ready' $fin
  } else {
    $fin = "Folder:     $InstallDir`nStart:      double-click start-all.bat in that folder`nStop:       type stop in the server window (end in the proxy window)`nSame network: ${Lan}:$Port`n"
    switch ("${Net}:$Tunnel") {
      'tunnel:playit' {
        if ($script:PublicAddr) { $fin += "`nplayit.gg tunnel. Friends connect to:`n>> $($script:PublicAddr)`nKeep playit running (and the tunnel pointed at 127.0.0.1:$Port) while you play.`n" }
        else { $fin += "`nplayit.gg tunnel is not finished yet. Run  powershell -File mc-setup.ps1 -TunnelGuide  for the step-by-step guide.`n" }
      }
      'tunnel:ngrok' {
        $fin += "`nngrok tunnel: friends connect to the address ngrok shows after tcp:// (e.g. 0.tcp.eu.ngrok.io:12345).`n"
        if (-not $NgrokToken) { $fin += "Add your token first:  `"$InstallDir\tools\ngrok.exe`" config add-authtoken <TOKEN> --config `"$InstallDir\tools\ngrok.yml`"`n" }
      }
      'tunnel:none' { $fin += "`nPoint your own tunnel at TCP 127.0.0.1:$Port.`n" }
      default {
        if ($Net -eq 'portfwd') {
          $Pub = Get-PublicIp
          if ($UpnpOk) { $fin += "`nPort forwarding via UPnP is active. Friends connect to:`n>> ${Pub}:$Port`n" }
          else { $fin += "`nPort forwarding - do this on your router's admin page (often http://192.168.0.1 or 192.168.1.1):`n Forward TCP port $Port -> $Lan port $Port`n Tip: give this PC a fixed IP in the router's DHCP settings.`nFriends then connect to:`n>> ${Pub}:$Port`nThis does not work if your ISP uses CGNAT - use a tunnel instead.`n" }
        }
      }
    }
    if ($script:Bedrock) {
      $bj = "$Lan  port $($script:BedrockPort)"
      if ($Net -eq 'tunnel' -and $Tunnel -eq 'playit') { $bj = 'not set up yet - run  powershell -File mc-setup.ps1 -TunnelGuide'; if ($script:PublicAddrBe) { $bj = "$($script:PublicAddrBe)   (address and port in the two Bedrock boxes)" } }
      elseif ($Net -eq 'portfwd') { $bj = "${Pub}:$($script:BedrockPort)   (forward UDP $($script:BedrockPort) on your router too)" }
      $fin += "`nBedrock players (UDP $($script:BedrockPort)):  $bj`nBedrock player names get a dot in front (for example .Steve) because of Floodgate.`n"
    }
    if (-not $Online) { $fin += "`nOffline mode is ON: anyone can join with any name. Keep the whitelist on!`n" }
    $fin += "`nMake yourself admin: in the server console type   op <YourName>"
    Show-Box 'Your server is ready' $fin
  }

  if (Ask-YesNo 'Start the server now?' $true) {
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$InstallDir\start-all.bat`"" -WorkingDirectory $InstallDir
  }
  Out-Raw "$cG$($Sym.end)$cR  $(L 'All set - have fun!')`n"
}
catch {
  if ($_.Exception.Message -eq 'MCSETUP_CANCEL') { exit 0 }
  if ($_.Exception.Message -ne 'MCSETUP_ABORT') {
    Out-Raw "$cRed$($Sym.err)  Something went wrong: $($_.Exception.Message)$cR`n"
    Out-Raw "$cGr   at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())$cR`n$cRed$($Sym.end)$cR`n" 
  }
  exit 1
}
