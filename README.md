QuackWorks is an OpenSCAD project centered around parametric functional prints. 

There are currently two publicly released collections: 
1. Underware - Infinite Cable Management (https://makerworld.com/en/models/783010)
2. BJD's Multiconnect Part Generators (https://makerworld.com/en/models/582260)
Web version is available here: 

Example in OpenSCAD
![image](https://github.com/user-attachments/assets/1fb201eb-66d4-4f9b-b52b-4cf9fbe7a652)

Multiconnect Development Standards
- Backer Standards
    - Back types as a single module accepting height and width parameters
    - All customizable parameters for a back type must be enclosed in their own parameter section
- Positioning Standards
    - Model starts at X 0 and goes positive
    - Back starts at X 0 and goes negative
    - Center the entire unit on x axis last
- Testing Critiera
    - Compiles without error
    - Test items under 5mm in height, depth, and width and verify back generates properly
    - Test for very large items

Shield: [![CC BY-NC-SA 4.0][cc-by-nc-sa-shield]][cc-by-nc-sa]

This work is licensed under a
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License][cc-by-nc-sa].

[![CC BY-NC-SA 4.0][cc-by-nc-sa-image]][cc-by-nc-sa]

[cc-by-nc-sa]: http://creativecommons.org/licenses/by-nc-sa/4.0/
[cc-by-nc-sa-image]: https://licensebuttons.net/l/by-nc-sa/4.0/88x31.png
[cc-by-nc-sa-shield]: https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg
