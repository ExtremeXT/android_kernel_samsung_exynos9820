# ExtremeKernel for Exynos 9820 devices

## Features

- SuSFS 1.5.5

## Supported devices:

G970F - S10e - beyond0lte

G970N - S10e (Korean) - beyond0lteks

G973F - S10 - beyond1lte

G973N - S10 (Korean) - beyond1lteks

G975F - S10+ - beyond2lte

G975N - S10+ (Korean) - beyond2lteks

G977B - S10 5G - beyondx

G977N - S10 5G (Korean) - beyondxks

N970F - Note 10 - d1

N971N - Note 10 5G (Korean) - d1xks

N975F - Note 10+ - d2s

N976B - Note 10+ 5G - d2x

N976N - Note 10+ 5G (Korean) - d2xks

## Build instructions:

1. Set up build environment as per Google documentation

https://source.android.com/docs/setup/start/requirements

2. Properly clone repository with submodules (KernelSU and toolchains)

```git clone --recurse-submodules https://github.com/ExtremeXT/android_kernel_samsung_exynos9820.git```

3. Build for your device

```./build.sh -m beyond2lte```

4. Fetch the flashable zip of the kernel that was just compiled

```build/out/[your_device]/ExtremeKernel...zip```

5. Flash it using a supported recovery like TWRP

6. Enjoy!
