from __future__ import annotations

import os
import re
import shutil
import bz2
from dataclasses import dataclass
from pathlib import Path

from fastapi import UploadFile

from .models import IsoImage


SAFE_NAME = re.compile(r"[^a-zA-Z0-9_.-]+")
SUPPORTED_MEDIA_EXTENSIONS = (".iso", ".img")
SUPPORTED_COMPRESSED_EXTENSIONS = (".img.bz2",)


@dataclass
class IsoStore:
    path: Path

    @classmethod
    def default(cls) -> "IsoStore":
        path = Path(os.environ.get("CAMONAS_ISO_STORE", "/var/lib/camonas/isos"))
        if not os.access(path.parent, os.W_OK):
            path = Path.home() / ".camonas" / "isos"
        return cls(path=path)

    def list(self) -> list[IsoImage]:
        self.path.mkdir(parents=True, exist_ok=True)
        images = []
        for item in sorted(self.path.iterdir()):
            if not item.is_file() or not self._is_supported_media_name(item.name):
                continue
            images.append(
                IsoImage(
                    name=item.name,
                    path=str(item),
                    size_mb=round(item.stat().st_size / 1024 / 1024, 2),
                )
            )
        return images

    def import_path(self, source: str) -> IsoImage:
        src = Path(source).expanduser()
        if not src.exists() or not src.is_file():
            raise ValueError("Installer media path does not exist.")
        if not self._is_supported_upload_name(src.name):
            raise ValueError("Selected file must be an .iso, .img, or .img.bz2 image.")
        self.path.mkdir(parents=True, exist_ok=True)
        dest = self.path / self._safe_name(self._stored_filename(src.name))
        if self._is_compressed_image(src.name):
            self._decompress_bz2(src, dest)
        else:
            shutil.copyfile(src, dest)
        return IsoImage(name=dest.name, path=str(dest), size_mb=round(dest.stat().st_size / 1024 / 1024, 2))

    async def upload(self, upload: UploadFile) -> IsoImage:
        original_name = upload.filename or "installer.iso"
        if not self._is_supported_upload_name(original_name):
            raise ValueError("Uploaded file must use the .iso, .img, or .img.bz2 extension.")
        filename = self._safe_name(self._stored_filename(original_name))
        self.path.mkdir(parents=True, exist_ok=True)
        dest = self.path / filename
        if self._is_compressed_image(original_name):
            decompressor = bz2.BZ2Decompressor()
            with dest.open("wb") as handle:
                while True:
                    chunk = await upload.read(1024 * 1024)
                    if not chunk:
                        break
                    handle.write(decompressor.decompress(chunk))
        else:
            with dest.open("wb") as handle:
                while True:
                    chunk = await upload.read(1024 * 1024)
                    if not chunk:
                        break
                    handle.write(chunk)
        return IsoImage(name=dest.name, path=str(dest), size_mb=round(dest.stat().st_size / 1024 / 1024, 2))

    def _safe_name(self, value: str) -> str:
        safe = SAFE_NAME.sub("-", Path(value).name).strip(".-")
        return safe or "installer.iso"

    def _is_supported_media_name(self, value: str) -> bool:
        return value.lower().endswith(SUPPORTED_MEDIA_EXTENSIONS)

    def _is_supported_upload_name(self, value: str) -> bool:
        lower = value.lower()
        return lower.endswith(SUPPORTED_MEDIA_EXTENSIONS) or lower.endswith(SUPPORTED_COMPRESSED_EXTENSIONS)

    def _is_compressed_image(self, value: str) -> bool:
        return value.lower().endswith(SUPPORTED_COMPRESSED_EXTENSIONS)

    def _stored_filename(self, value: str) -> str:
        if self._is_compressed_image(value):
            return value[:-4]
        return value

    def _decompress_bz2(self, source: Path, dest: Path) -> None:
        with bz2.open(source, "rb") as src, dest.open("wb") as output:
            shutil.copyfileobj(src, output, length=1024 * 1024)
