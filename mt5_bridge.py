#!/usr/bin/env python3
"""
MT5 Bridge — pont local entre MT5 (via EA MQL5) et le journal de trading.

Fonctionnement :
  1. Le journal appelle GET http://localhost:5001/mt5
  2. Le bridge écrit mt5_trigger.txt dans le dossier MQL5/Files de MT5
  3. L'EA JournalExport.mq5 détecte le trigger (timer 1s), exporte
     closed_trades.json, puis supprime le trigger
  4. Le bridge attend le fichier (max 10s) et le renvoie en JSON

Usage :
  python3 mt5_bridge.py --mt5-files "/chemin/vers/MQL5/Files"

Trouver le dossier MQL5/Files dans MT5 :
  MT5 → File → Open Data Folder → MQL5 → Files
  Sur Mac (CrossOver / Wine MetaQuotes) : chemin dans ~/Library/Application Support/...
"""

import sys
import os
import time
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

DEFAULT_PORT = 5001
MT5_FILES_PATH = "/Users/antoinedesreumaux/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/crossover/AppData/Roaming/MetaQuotes/Terminal/Common/Files"


class Handler(BaseHTTPRequestHandler):
    mt5_files = MT5_FILES_PATH

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path.split("?")[0] != "/mt5":
            self.send_response(404)
            self.end_headers()
            return

        mt5_dir = Handler.mt5_files

        # Vérifier que le dossier MQL5/Files est configuré
        if not mt5_dir or not os.path.isdir(mt5_dir):
            self._json(503, {
                "error": (
                    f"Dossier MQL5/Files non trouvé : '{mt5_dir}'\n"
                    "Relancer avec : python3 mt5_bridge.py --mt5-files \"/chemin/MQL5/Files\"\n"
                    "Trouver le chemin dans MT5 : File → Open Data Folder → MQL5 → Files"
                )
            })
            return

        trigger = os.path.join(mt5_dir, "mt5_trigger.txt")
        output  = os.path.join(mt5_dir, "closed_trades.json")

        # Supprimer un éventuel ancien fichier output
        if os.path.exists(output):
            try:
                os.remove(output)
            except OSError:
                pass

        # Écrire le trigger → l'EA MQL5 va réagir
        try:
            with open(trigger, "w") as f:
                f.write("refresh")
        except OSError as e:
            self._json(500, {"error": f"Impossible d'écrire le trigger : {e}"})
            return

        print(f"[MT5 bridge] Trigger envoyé → en attente de closed_trades.json…")

        # Attendre que l'EA produise le fichier JSON (max 10s)
        deadline = time.time() + 10
        while time.time() < deadline:
            if os.path.isfile(output):
                time.sleep(0.15)  # laisser l'EA finir l'écriture
                try:
                    with open(output, "r", encoding="utf-8") as f:
                        content = f.read()
                    body = content.encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json; charset=utf-8")
                    self.send_header("Content-Length", str(len(body)))
                    self._cors()
                    self.end_headers()
                    self.wfile.write(body)
                    # Compter les trades pour le log
                    try:
                        n = len(json.loads(content))
                        print(f"[MT5 bridge] {n} trades servis.")
                    except Exception:
                        pass
                    return
                except OSError as e:
                    self._json(500, {"error": f"Lecture closed_trades.json échouée : {e}"})
                    return
            time.sleep(0.2)

        # Timeout
        self._json(504, {
            "error": "Timeout (10s) : MT5 n'a pas répondu.\n"
                     "Vérifier que JournalExport.mq5 est compilé et attaché à un graphique."
        })

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # silencieux (on gère nos propres logs)


if __name__ == "__main__":
    args = sys.argv[1:]
    port = DEFAULT_PORT

    for i, a in enumerate(args):
        if a == "--mt5-files" and i + 1 < len(args):
            Handler.mt5_files = os.path.expanduser(args[i + 1])
        elif a == "--port" and i + 1 < len(args):
            port = int(args[i + 1])

    print("=" * 60)
    print(f"MT5 Bridge → http://localhost:{port}/mt5")
    if Handler.mt5_files and os.path.isdir(Handler.mt5_files):
        print(f"MQL5/Files  → {Handler.mt5_files}  ✓")
    else:
        print(f"MQL5/Files  → NON CONFIGURÉ")
        print()
        print("  Lancer avec :")
        print('  python3 mt5_bridge.py --mt5-files "/chemin/vers/MQL5/Files"')
        print()
        print("  Trouver le chemin dans MT5 :")
        print("  File → Open Data Folder → MQL5 → Files")
    print("  (Ctrl+C pour stopper)")
    print("=" * 60)

    HTTPServer(("localhost", port), Handler).serve_forever()
