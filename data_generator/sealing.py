"""Scellement du scénario caché (tâche 1.6, docs/01, section 6).

Le scénario caché (histoires, taux de défauts, graine, période cachée) est :
- chiffré, pour ne pas être lu par accident (recherche dans VS Code, git diff) ;
- verrouillé par son empreinte SHA-256, commitée avant toute analyse :
  elle prouve à la révélation qu'il n'a pas été modifié après coup.

Trois fonctions :
- seal_scenario   : calcule l'empreinte du scénario en clair, puis le chiffre ;
- load_scenario   : déchiffre le scénario en mémoire, pour le générateur ;
- verify_scenario : à la révélation, compare le scénario publié à l'empreinte.
"""

import hashlib
import os
from pathlib import Path

import yaml
from cryptography.fernet import Fernet
from dotenv import load_dotenv

ENCRYPTED_PATH = Path("config/delta_plus/sealed_scenario.enc")  # ignoré par Git (sealed_*)
FINGERPRINT_PATH = Path("config/delta_plus/scenario_fingerprint.txt")  # commité
KEY_VARIABLE = "SCENARIO_KEY"  # rangée dans .env, jamais dans Git
ENV_PATH = Path(".env")


def compute_fingerprint(content: bytes) -> str:
    """Empreinte SHA-256 d'un contenu : 64 caractères hexadécimaux."""
    return hashlib.sha256(content).hexdigest()


def seal_scenario(plain_path: Path, env_path: Path) -> None:
    """Scelle un scénario en clair.

    Écrit le fichier chiffré et l'empreinte dans config/delta_plus/,
    et la clé dans le fichier .env. Rien n'est affiché à l'écran.
    """
    content = plain_path.read_bytes()

    fingerprint = compute_fingerprint(content)
    key = Fernet.generate_key()
    encrypted = Fernet(key).encrypt(content)

    ENCRYPTED_PATH.write_bytes(encrypted)
    FINGERPRINT_PATH.write_text(fingerprint + "\n")

    with env_path.open("a") as env_file:
        env_file.write(f"\n{KEY_VARIABLE}={key.decode()}\n")


def load_scenario() -> dict:
    """Déchiffre le scénario en mémoire, sans l'écrire sur le disque.

    Vérifie au passage que le contenu correspond à l'empreinte commitée :
    le générateur refuse de tourner sur un scénario modifié.
    """
    load_dotenv(ENV_PATH)
    key = os.environ[KEY_VARIABLE]

    content = Fernet(key.encode()).decrypt(ENCRYPTED_PATH.read_bytes())

    expected = FINGERPRINT_PATH.read_text().strip()
    if compute_fingerprint(content) != expected:
        raise ValueError("Le scénario ne correspond pas à l'empreinte commitée.")

    return yaml.safe_load(content)


def verify_scenario(published_path: Path) -> bool:
    """À la révélation : le scénario publié est-il celui qui a été scellé ?"""
    published = published_path.read_bytes()
    expected = FINGERPRINT_PATH.read_text().strip()
    return compute_fingerprint(published) == expected
