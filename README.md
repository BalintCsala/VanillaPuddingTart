## Before you try it out, read this!

**Slight epilepsy warning**, the shader generates a lot of noise (this is by design, imagine a very colorful TV static). Don't try it out if you are prone to seizures. This will be remedied in a future patch.

This shader is WIP, therefore it lacks many features, including complete support for 90% of the blocks. If you still want to try it out, do it in a void world, but don't expect a playable resource pack.

# Path tracing 1.17 shader

## Features

 - Path traced global illumination
 - Shadows
 - Reflections
 - Emission (= light sources work as they should)
 - Configurable (kinda) IOR and metallicity factors

## How to install

Usually works on the current snapshot, but make sure to check the last commit date! If it doesn't work on the latest and the date is before the release date of the snapshot, then I probably haven't gotten around to updating it yet.

This also only works if the resolution of your monitors exceeds or matches 1024x768 in both directions

 1. Press the green `⤓ Code` button and select "Download ZIP"
 2. Extract the content of the ZIP file to your resource pack folder
 3. Start the game and enter into a world (a superflat with the void preset is a good starting point, as most normal worlds don't work)
 4. Go into video settings and set Graphics to _Fabulous!_
 5. Go into resource packs and enable the path tracing resource pack. Make sure to disable anything else, even if they don't have shaders.

## Examples

These images were taken without any noise reduction. Looks less noisy in-game.

![example1](images/gi-example1.png)

![example2](images/gi-example2.png)

![example3](images/gi-example3.png)
