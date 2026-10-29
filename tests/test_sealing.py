"""Tests du scellement, sur un faux scénario (jamais le vrai)."""

from pathlib import Path

import pytest

from data_generator import sealing

FAKE_SCENARIO = "seed: 42\neffects:\n  - effect_id: E99\n    magnitude: -0.15\n"


@pytest.fixture
def project(tmp_path, monkeypatch):
    """Un faux dossier de projet, pour ne jamais toucher au vrai scénario."""
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv(sealing.KEY_VARIABLE, raising=False)
    (tmp_path / "config" / "delta_plus").mkdir(parents=True)
    plain_path = tmp_path / "scenario.yml"
    plain_path.write_text(FAKE_SCENARIO)
    env_path = tmp_path / ".env"
    env_path.write_text("")
    return plain_path, env_path


def test_sealed_file_is_not_readable(project):
    plain_path, env_path = project
    sealing.seal_scenario(plain_path, env_path)
    encrypted = sealing.ENCRYPTED_PATH.read_bytes()
    assert b"E99" not in encrypted


def test_scenario_round_trip(project):
    plain_path, env_path = project
    sealing.seal_scenario(plain_path, env_path)
    scenario = sealing.load_scenario()
    assert scenario["effects"][0]["effect_id"] == "E99"


def test_published_scenario_matches_fingerprint(project):
    plain_path, env_path = project
    sealing.seal_scenario(plain_path, env_path)
    assert sealing.verify_scenario(plain_path)


def test_one_changed_character_is_detected(project, tmp_path):
    plain_path, env_path = project
    sealing.seal_scenario(plain_path, env_path)
    altered_path = tmp_path / "altered.yml"
    altered_path.write_text(FAKE_SCENARIO.replace("-0.15", "-0.16"))
    assert not sealing.verify_scenario(altered_path)
