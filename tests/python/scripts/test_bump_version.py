"""Tests for scripts/bump-version.py."""

import pytest
from pathlib import Path

from conftest import _import_module_from_path, SCRIPTS_DIR


@pytest.fixture
def bump_version():
    return _import_module_from_path("bump_version", SCRIPTS_DIR / "bump-version.py")


class TestBump:
    def test_patch(self, bump_version):
        assert bump_version.bump("0.2.0", "patch") == "0.2.1"

    def test_minor(self, bump_version):
        assert bump_version.bump("0.2.0", "minor") == "0.3.0"

    def test_major(self, bump_version):
        assert bump_version.bump("0.2.0", "major") == "1.0.0"

    def test_explicit_version(self, bump_version):
        assert bump_version.bump("0.2.0", "1.5.0") == "1.5.0"


class TestParseVersion:
    def test_valid(self, bump_version):
        assert bump_version.parse_version("1.2.3") == (1, 2, 3)

    def test_invalid_exits(self, bump_version):
        with pytest.raises(SystemExit):
            bump_version.parse_version("invalid")


class TestReadCurrentVersion:
    def test_reads_file(self, bump_version):
        version = bump_version.read_current_version()
        assert version
        parts = version.split(".")
        assert len(parts) == 3


class TestUpdateFile:
    def test_updates_content(self, bump_version, tmp_path):
        f = tmp_path / "test.sh"
        f.write_text('VERSION="0.2.0"\n')
        result = bump_version.update_file(
            str(f),
            r'(VERSION=")[^"]*(")',
            r"\g<1>{version}\2",
            "0.3.0",
        )
        assert result is True
        assert '0.3.0' in f.read_text()

    def test_no_match_returns_false(self, bump_version, tmp_path):
        f = tmp_path / "test.sh"
        f.write_text("no match here\n")
        result = bump_version.update_file(
            str(f),
            r'(VERSION=")[^"]*(")',
            r"\g<1>{version}\2",
            "0.3.0",
        )
        assert result is False
