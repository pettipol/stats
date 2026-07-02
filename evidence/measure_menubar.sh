#!/bin/zsh
# measure_menubar.sh — diagnostica posizionamento status item barra dei menu (macOS Tahoe).
# Uso: zsh /Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh
# Sola lettura. Distingue item ORFANO (fuori barra, y grande) da OK (in barra, y piccola).
# Filtra i "fantasma" AX per dimensione 0x0 (robusto su qualsiasi risoluzione/arrangiamento).

echo "=== Processi Bartender / NotchBar (attesi ASSENTI dopo la disinstallazione) ==="
pgrep -lf -i bartender || echo "  nessun Bartender"
pgrep -lf -i notchbar  || echo "  nessun NotchBar"
echo

echo "=== Display (risoluzione, main) ==="
system_profiler SPDisplaysDataType 2>/dev/null \
  | grep -Ei 'Resolution|UI Looks like|Main Display|Rotation|Mirror' | head -20
echo

echo "=== FOCUS: Stats + Backblaze (bzbmenu) — verdetto per item reale ==="
osascript <<'EOF' 2>&1
tell application "System Events"
  set out to ""
  repeat with pname in {"Stats", "bzbmenu"}
    try
      tell process pname
        set nReal to 0
        repeat with mb in menu bars
          repeat with anItem in (menu bar items of mb)
            try
              set sz to size of anItem
              if (item 1 of sz) > 0 then -- item reale (non fantasma 0x0)
                set nReal to nReal + 1
                set p to position of anItem
                set py to (item 2 of p)
                if py > 100 then
                  set out to out & pname & "  pos=" & (item 1 of p) & "," & py & "   <-- ORFANO (fuori barra)" & linefeed
                else
                  set out to out & pname & "  pos=" & (item 1 of p) & "," & py & "   <-- OK (in barra)" & linefeed
                end if
              end if
            end try
          end repeat
        end repeat
        if nReal = 0 then set out to out & pname & "  (0 item reali — forse ancora in avvio)" & linefeed
      end tell
    on error
      set out to out & pname & "  <processo non trovato>" & linefeed
    end try
  end repeat
  return out
end tell
EOF
echo

echo "=== CONTRASTO: campione di app che devono stare in barra ==="
osascript <<'EOF' 2>&1
tell application "System Events"
  set out to ""
  set names to {"Ollama", "OneDrive", "Rectangle", "AltTab", "Parallels Toolbox", "CPU Temperature", "Google Drive", "DeepL"}
  repeat with pname in names
    try
      tell process pname
        set verdict to "?"
        repeat with mb in menu bars
          repeat with anItem in (menu bar items of mb)
            try
              set sz to size of anItem
              if (item 1 of sz) > 0 then
                set py to (item 2 of (position of anItem))
                if py > 100 then
                  set verdict to "ORFANO(y=" & py & ")"
                else
                  set verdict to "in barra"
                end if
              end if
            end try
          end repeat
        end repeat
        set out to out & "  " & pname & ": " & verdict & linefeed
      end tell
    end try
  end repeat
  return out
end tell
EOF