"""
Módulo compartilhado de logging para scripts Python do Spellbook-OS.

Cria logger com RotatingFileHandler (5MB, 3 arquivos) em
$XDG_STATE_HOME/zsh-scripts/<nome>.log e também escreve em stderr.

Uso:
    from _logging import setup_logger
    log = setup_logger("meu-script")
    log.info("mensagem")
    log.warning("aviso")
    log.error("erro")
"""
import logging
import logging.handlers
import os
from pathlib import Path

_DEFAULT_LEVEL = logging.INFO
_MAX_BYTES = 5 * 1024 * 1024
_BACKUP_COUNT = 3


def log_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
    d = Path(base) / "zsh-scripts"
    d.mkdir(parents=True, exist_ok=True)
    return d


def setup_logger(
    name: str,
    level: int = _DEFAULT_LEVEL,
    stderr: bool = True,
    file: bool = True,
) -> logging.Logger:
    """
    Retorna logger configurado com rotação de arquivo e opcionalmente stderr.

    Idempotente: chamar múltiplas vezes com mesmo nome não duplica handlers.
    """
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    logger.setLevel(level)
    fmt = logging.Formatter(
        fmt="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    if file:
        log_path = log_dir() / f"{name}.log"
        fh = logging.handlers.RotatingFileHandler(
            log_path,
            maxBytes=_MAX_BYTES,
            backupCount=_BACKUP_COUNT,
            encoding="utf-8",
        )
        fh.setFormatter(fmt)
        fh.setLevel(level)
        logger.addHandler(fh)

    if stderr:
        sh = logging.StreamHandler()
        sh.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
        sh.setLevel(level)
        logger.addHandler(sh)

    logger.propagate = False
    return logger
