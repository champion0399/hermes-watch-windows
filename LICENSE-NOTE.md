# Note

This guide documents a personal sideloading workflow for HermesEnabler using
xtool on a free Apple ID. It is provided as-is for educational purposes.

HermesEnabler itself is https://github.com/pookjw/HermesEnabler — see its own
license/terms. xtool is https://github.com/xtool-org/xtool.

The `watch-device-helper` scripts are based on pymobiledevice3
(https://github.com/doronz88/pymobiledevice3), MIT-style.

The xtool patch also includes the locally modified `Vendor/zsign` sources
required to build the Watch-capable signer. Its MIT license and the bundled
zlib/MiniZip copyright and license notices are retained within the patch.
See the resulting `Vendor/zsign/LICENSE` and the notices in its source files.
