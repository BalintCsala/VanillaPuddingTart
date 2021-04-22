# Path tracing 1.17 shader

Disclaimer: This shader is WIP. It is not complete in any shape or form, it still has the following very obvious problems:
 - No support for non-full blocks, translucent blocks and blocks with different textures on some sides
 - Dawn and night just straight up breaks it, only play at noon
 - Some camera glitches
 - No view bobbing
 - Some screen resolutions probably (anything above a 720p screen _should_ work)

## How to install

 1. Press the green `⤓ Code` button and select "Download ZIP"
 2. Extract the content of the ZIP file to your resource pack folder
 3. If your screen resolution isn't 1920x1080 or you are playing in fullscreen, do the following (This step will hopefully be removed shortly):
    1. Open Minecraft and load into a world.
    2. Press F3 and note down the screen size. This can be found on the right side after `Display:`
       
       ![resolution](images/resolution.png)
    3. Go into the folder you extracted and go to the path `assets/minecraft/shaders/core`
    4. Look for the file `rendertype_solid.json` and open it with a text editor
    5. Look for the line
     
    ```{ "name": "ScreenSize", "type": "float", "count": 2, "values": [ 1920.0, 1017.0 ] }```
    6. Carefully edit the last two numbers to the width and height you got at step `ii.`. Make sure to use dots and not commas for the decimal point!
 4. Start the game and enter into a world (a superflat with the void preset is a good starting point, as most normal worlds don't work)
 5. Go into video settings and set Graphics to _Fabulous!_
 6. Go into resource packs and enable the path tracing resource pack. Make sure to disable anything else, even if they don't have shaders.