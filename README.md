# Minecraft server setup

Sets up your own Minecraft (Java Edition) server by asking a few questions.

## Features

- Vanilla, Paper (plugins) or Paper + Velocity; Java only, or Java + Bedrock with Geyser/Floodgate
- Free tunnel (playit.gg or ngrok) with a step-by-step guide, or port forwarding / UPnP
- Online or offline mode, automatic Java, start/stop scripts, optional autostart
- Simple and Advanced setup, a version picker, a plugin/mod picker
- A second tool to change a server later, with backups first
- 14 languages, including right-to-left Hebrew and Arabic
- Windows, macOS and Linux

Downloads are on the **Releases** page: `mc-setup-windows.zip`, `mc-setup-mac.zip`, `mc-setup-linux.tar.gz` (or `.zip`).

## Run it

**Windows:** unzip, then double-click **`mc-setup.bat`** (keep `mc-setup.ps1` next to it).

**Linux (Ubuntu/Debian, Fedora, Arch, openSUSE, Alpine):** download `mc-setup-linux.tar.gz` (or the `.zip`), then:

```
tar xzf mc-setup-linux.tar.gz && cd mc-setup-linux && ./mc-setup.sh
```

(From the .zip: `unzip mc-setup-linux.zip && cd mc-setup-linux && chmod +x *.sh && ./mc-setup.sh`.)
Works over SSH and on servers without a desktop. It finds your package manager (apt, dnf, pacman, zypper, apk) to install Java, curl, jq and tmux,
and uses `sudo` only when it needs it. Without sudo it still works, it just tells you what to ask an administrator for (firewall port, missing packages).
Autostart uses a systemd **user** service (`systemctl --user status minecraft`) with "linger" so it starts at boot; a system service is used only if no user session exists.
Links open with `xdg-open` when there is a desktop, otherwise they are printed for you to open on another computer. Change a server later with `./mc-customize.sh`.

**Mac (Intel or Apple Silicon):** unzip `mc-setup-mac.zip`, then double-click **`mc-setup.command`**.
The first time macOS may say it "cannot be opened": right-click the file, choose **Open**, then **Open** again.
If double-click does nothing, open Terminal and run: `cd` to the folder, then `chmod +x mc-setup.command mc-setup.sh && ./mc-setup.command`.
macOS ships an old bash, so the first run offers a one-time install of a newer one with Homebrew (it installs Homebrew too if needed).
Java is downloaded automatically. Your server also gets `Start Server.command` and `Stop Server.command` to double-click.

## Languages

The first screen lets you pick a language: English, 中文, हिन्दी, العربية, עברית, Español, Français,
Deutsch, Português, Русский, 日本語, 한국어, Türkçe, Italiano. Your system language is preselected.
Skip the screen with `--lang de` (Linux) or `-Lang de` (Windows), or `MCS_LANG=de`.

* The setup questions, menus (including Customise and the customise-later tool), summary and final
  screen are translated. Some detailed screens (error details, the playit tunnel guide steps,
  plugin descriptions) are still English.
* Chinese, Japanese, Korean, Hindi, Arabic and Hebrew need a terminal font that can show them
  (Windows Terminal or any modern Linux terminal). If you see squares, choose English.
* Arabic and Hebrew: most terminals (including Windows Terminal) do not reorder right-to-left text, so the
  program converts it itself, once, for every line. If your terminal already shows it correctly and you
  see it backwards, set `MCS_BIDI=1` (turns the conversion off). `MCS_BIDI=0` forces it on.
* Add a language: create `lang/<code>.txt` next to the script with lines of
  `English text<TAB>translation` (copy the format from the data blocks in the script).

## Simple or Advanced

The first screen asks which one you want:

* **Simple** (recommended): you answer a few questions - the server name, the kind of server,
  whether Bedrock players (phones, consoles, Windows 10/11) can join too, how friends will join, and
  whether everyone owns Minecraft. Then you pick the Minecraft version: the newest is the default
  (just press Enter), or choose an older one from the list or type it. Everything else is chosen
  for you (Java, memory, port).
* **Advanced**: you choose every option, and there is a **Customise** menu for the server message
  (with colours), icon, mods and plugins, operators and whitelist, world and gameplay settings,
  resource pack, auto-restart and backups.

## Java and Bedrock (Geyser)

Answer **Yes** to "Should Bedrock players ... be able to join too?" (Simple), or to "Also let Bedrock
players join" (Advanced), and the script installs **Geyser** and **Floodgate** on a PaperMC server.
Bedrock players then join without a Java account.

* Geyser needs Paper, so a Vanilla choice is switched to Paper automatically. It is not offered with the
  Velocity proxy setup.
* Bedrock uses **UDP port 19132** (the script opens it in the firewall and through UPnP where it can).
* Floodgate puts a **dot in front of Bedrock player names** (for example `.Steve`) so they never clash with
  Java names. Mention this to your Bedrock friends and when you add them to the whitelist or as operators.
* With playit.gg you need a **second tunnel** of type *Minecraft Bedrock* (UDP, local port 19132). The
  tunnel guide adds that step and asks for both addresses. The final screen shows both: Java players use
  the Java address, Bedrock players type the Bedrock address and its port in the two Bedrock boxes.
* Geyser and Floodgate are downloaded from geysermc.org as the newest builds. If Bedrock players cannot
  join after a Minecraft update, update the two jars (use the customise tool or re-download them).

## Change a server later (customise tool)

Run **`mc-customize.bat`** (Windows), **`./mc-customize.sh`** (Linux) or **`mc-customize.command`** (Mac).
It finds servers made by this tool (or lets you browse for the folder) and opens the same menus:
name, server message, icon, add / remove plugins or mods, operators and whitelist, world, gameplay,
performance, resource pack, extra properties, auto-restart and backups. It can also:

* **change the Minecraft version** (a full backup goes into the `backups` folder first),
* **turn Bedrock support on or off** (switches Vanilla to Paper, with a backup),
* **make a backup now**.

Removed plugins and mods are moved to a folder called `removed`, not deleted. Stop the server first;
changes are read the next time it starts. The tool only changes the settings you touch; the rest of
`server.properties` stays as it is. Keep `mc-customize` next to `mc-setup` (it uses the same code).

## Plugins and mods

In **Advanced > Customise > Plugins** (or **Mods** for Vanilla) pick from a ready-made list of
popular ones (EssentialsX, LuckPerms, WorldEdit, Geyser, ViaVersion, ...). Only the ones that
work with your Minecraft version are shown; tick with Space, press Enter. You can still search
Modrinth, add links, or review the queue.

The list grows over time: add a line `modrinth-slug|Name|Description` to `plugins.list` (or
`mods.list`) next to the script, or to the table at the top of the script.

Tip: use a modern terminal (Windows Terminal) for the best look; arrow keys choose, Enter confirms.

## Where it is saved

After you name your server, you pick where it goes: next to the script (recommended), on your
Desktop, in Documents, in your home folder, or somewhere else (Windows opens a folder picker). A new folder named after
your server is created there, and you see the full path before anything is installed.

## Start your server

* **Windows:** double-click **`start-all.bat`** in your server folder.
* **Linux:** run `start-all.sh --attach` from your server folder.
* **Mac:** double-click **`Start Server.command`** in your server folder.

To stop it, type `stop` in the server window.

## How friends join

* **Over the internet (free tunnel):** the script walks you through playit.gg one small step at a
  time (make an account, install playit, claim it, create a Minecraft Java tunnel, copy the address).
  The address you paste is saved and shown at the end. To run the guide again later:
  `powershell -File mc-setup.ps1 -TunnelGuide` (Windows) or `./mc-setup.sh --tunnel-guide` (Linux).
  Keep playit running while you play.
* **Port forwarding:** the script tries to open the port on your router automatically and shows
  the address to share. If your internet provider doesn't allow it, use the tunnel instead.
* **Home Wi-Fi only:** friends use the address the script prints.

"Everyone owns Minecraft" means premium login. If you answer No, anyone can join with any name,
so only share the address with people you trust.

Your answers are saved in `mc-setup.conf`. To make yourself an admin, type `op YourName` in the
server window.

## License

MIT, see `LICENSE`.
