/*Created by SnazzyGreenWarrior and BlackjackDuck (Andy)

Documentation available at https://handsonkatie.com/underware-2-0-the-made-to-measure-collection/

Credit to 
    Katie and her community at Hands on Katie on Youtube, Patreon, and Discord
    SnazzyGreenWarrior for Keyhole design, logic, and testing
    Jonathan at Keep Making for Multiboard
    
All parts except for Snap Connector are Licensed Creative Commons 4.0 Attribution Non-Commercial Share-Alike (CC-BY-NC-SA)
Snap Connector adopts the Multiboard.io license at multiboard.io/license
*/

include <BOSL2/std.scad>
include <BOSL2/rounding.scad>
include <BOSL2/threading.scad>

/*[Choose Part]*/
//How do you intend to mount the channels to a surface such as Honeycomb Storage Wall or Multiboard? See options at https://handsonkatie.com/underware-2-0-the-made-to-measure-collection/
Show_Part = "Snap Keyhole"; // [Snap Keyhole, Keyhole Test]

/*[Options: Thread Snap Connector ]*/
//Height (in mm) the snap connector rests above the board. 3mm is standard. 0mm results in a flush fit. 
Snap_Connector_Height = 3;
//Scale of the Snap Connector holding 'bumpouts'. 1 is standard. 0.5 is half size. 1.5 is 50% larger. Large = stronger hold. 
Snap_Holding_Tolerance = 1; //[0.5:0.05:2.0]


/*[Advanced Options]*/
//Color of part (color names found at https://en.wikipedia.org/wiki/Web_colors)
Global_Color = "SlateBlue";
//Octogon Scaling - Decrease if the octogon is too large for the snap connector. Increase if the octogon is too small.
Oct_Scaling = 1; //[0.8:0.01:1.2]

/*[keyhole]*/
// Depth (in mm) from the flush surface of the object to the bottom of the keyhole (larger number)
keyholeTotalDepth=5.5;
// Depth of the throat of the key.
keyholeEntranceDepth=2.55;
// Diameter of the larger keyhole opening
keyholeEntraceDiameter=7.5;
// diameter of the smaller keyhole slot
keyholeSlotDiameter=4.1;
// Pick a point on a keyhole and measure (in mm) from that point to the same point on the other hole
distanceBetweenKeyholeEntranceCenters = 144; 


/*

MOUNTING PARTS

*/
if(Show_Part == "Snap Keyhole"){
    // Do all the math to handle keyhole offsets for the held item
    octogonScale = 1/sin(67.5);
    innerMostDiameter = (11.4465 * 2) * octogonScale;
    remainingOffset = 25 - (distanceBetweenKeyholeEntranceCenters % 25);
    remainingOffset2 = ( 25-(distanceBetweenKeyholeEntranceCenters % 25) <= 12.5) ? 25 - (distanceBetweenKeyholeEntranceCenters % 25) : (distanceBetweenKeyholeEntranceCenters % 25);
    offsetToEdge = (innerMostDiameter - (keyholeEntraceDiameter)) / 2;
    keyhole1Offset = (remainingOffset2 < offsetToEdge) ? 0 : (remainingOffset2 * -0.5 );
    keyhole2Offset = (remainingOffset2 < offsetToEdge) ? remainingOffset2 : (remainingOffset2 * 0.5 );


    // make the parts
    union() recolor(Global_Color)
    split_Part(split_width=20, connect=BOT, largest_size = 50)
        make_keyhole_part(
            offset = Snap_Connector_Height, 
            anchor=BOT, 
            keyholeOffset=keyhole1Offset
            );
    
    
    recolor(Global_Color) fwd(30) 
    union(){ 
    split_Part(split_width=20, connect=BOT, largest_size = 50)
        make_keyhole_part(
            offset = Snap_Connector_Height, 
            anchor=BOT, 
            keyholeOffset=keyhole2Offset
            );
    }
    
    /* deprecated for new split_part module
    recolor(Global_Color){
    make_keyhole_part(  offset = Snap_Connector_Height, 
                        anchor=BOT, 
                        keyholeOffset=keyhole1Offset);
    fwd(25 - keyhole2Offset + keyhole1Offset) 
        make_keyhole_part(  offset = Snap_Connector_Height, 
                            anchor=BOT, 
                            keyholeOffset=keyhole2Offset);
    }
    */
    
};
if(Show_Part == "Keyhole Test"){
    recolor(Global_Color)
    make_keyhole_part(offset = Snap_Connector_Height, anchor=BOT, keyholeOffset=0, isTest=true);
};

// Main assembly for the keyhole maker. Link a stem to a snap
module make_keyhole_part (offset = 3, anchor=BOT,spin=0,orient=UP, keyholeOffset, isTest=false){
    attachable(anchor, spin, orient, size=[11.4465*2, 11.4465*2, 6.18+offset+keyholeTotalDepth-0.01]) {
        fwd (keyholeOffset) xrot(180) down((6.18+offset)/2)
        union(){
        make_keyhole_stem() 
            attach(TOP, TOP, overlap=0.02) 
                fwd(keyholeOffset){
                    if(isTest){
                        cyl(r=11.4465, h= 1.97);
                    }
                    else{
                    zrot(45)snapConnectBacker(
                            offset = offset, 
                            holdingTolerance = Snap_Holding_Tolerance, 
                            anchor = TOP, 
                            orient = UP);
                    }
                }
        }
    children();
    }
}

/* deprecated for new split_part module

module make_keyhole_part (offset = 3, anchor=BOT,spin=0,orient=UP, keyholeOffset, isTest=false){
    left(0.2+keyholeTotalDepth/2) yrot(-90) right_half()
        make_keyhole_stem() 
            attach(TOP, TOP) 
                fwd(keyholeOffset){
                    if(isTest){
                        cyl(r=11.4465, h= 1.97);
                    }
                    else{
                    snapConnectBacker(
                            offset = offset, 
                            holdingTolerance = Snap_Holding_Tolerance, 
                            anchor = TOP, 
                            orient = UP);
                    }
                }
    right(0.2+keyholeTotalDepth/2) yrot(90) left_half()
        make_keyhole_stem()
            attach(TOP, TOP)
                fwd(keyholeOffset){
                    if(isTest){
                        cyl(r=11.4465, h= 1.97);
                    }
                    else{
                        snapConnectBacker(
                            offset = offset, 
                            holdingTolerance = Snap_Holding_Tolerance, 
                            anchor = TOP, 
                            orient = UP);
                    }
                }
    cuboid([0.42,keyholeEntraceDiameter,0.2], anchor=BOT);
}
*/

// keyhole stem as a BOSL2 attachable.
module make_keyhole_stem(anchor=CENTER, spin=0, orient=UP) {
    attachable(anchor, spin, orient, d=keyholeEntraceDiameter, h=keyholeTotalDepth-0.01) {
        down(keyholeEntranceDepth/2)
            cyl(d=keyholeEntraceDiameter, h=keyholeTotalDepth-keyholeEntranceDepth)
            attach(TOP, BOT, overlap=0.01) 
                cyl(d=keyholeSlotDiameter, h=keyholeEntranceDepth);
        children();
    }
}

//SPLIT PART
//Split part takes a part and splits in half on the bed with a connector. This is often used for stronger connections in things like threads due to layer line orientation. 
module split_Part(split_distance=0.4, split_width=5, connect=TOP, largest_size = 50, connector_height = 0.2){
    union(){
        cuboid([split_distance+0.04, split_width, connector_height], anchor=BOT){
            xrot(-90) back(split_distance/4) attach(RIGHT, connect, overlap=0.02)
                left_half(s = largest_size*2) children();
            xrot(-90) back(split_distance/4)attach(LEFT, connect, overlap=0.02)
                right_half(s = largest_size*2) children();
        }
    }
}

module snapConnectBacker(offset = 0, holdingTolerance=1, anchor=CENTER, spin=0, orient=UP){
    attachable(anchor, spin, orient, size=[11.4465*2, 11.4465*2, 6.18+offset]){ 
    //bumpout profile
    bumpout = turtle([
        "ymove", -2.237,
        "turn", 40,
        "move", 0.557,
        "arcleft", 0.5, 50,
        "ymove", 0.252
        ]   );

    down((6.2+offset)/2)
    union(){
    diff("remove")
        //base
            oct_prism(h = 4.23, r = 11.4465*Oct_Scaling, anchor=BOT) {
                //first bevel
                attach(TOP, BOT, overlap=0.01) oct_prism(h = 1.97, r1 = 11.4465, r2 = 12.5125, $fn =8, anchor=BOT)
                    //top - used as offset. Independen snap height is 2.2
                    attach(TOP, BOT, overlap=0.01) oct_prism(h = offset, r = 12.9885, anchor=BOTTOM);
                        //top bevel - not used when applied as backer
                        //position(TOP) oct_prism(h = 0.4, r1 = 12.9985, r2 = 12.555, anchor=BOTTOM);
            
            //end base
            //bumpouts
            attach([RIGHT, LEFT, FWD, BACK],LEFT, shiftout=-0.01)  color("green") down(0.87) fwd(1)scale([1,1,holdingTolerance]) zrot(90)offset_sweep(path = bumpout, height=3);
            //delete tools
            //Bottom and side cutout - 2 cubes that form an L (cut from bottom and from outside) and then rotated around the side
            tag("remove") 
                 align(BOTTOM, [RIGHT, BACK, LEFT, FWD], inside=true, shiftout=0.01, inset = 1.6) 
                    color("lightblue") cuboid([0.8,7.161,3.4], spin=90*$idx)
                        align(RIGHT, [TOP]) cuboid([0.8,7.161,1], anchor=BACK);
            }
    }
    children();
    }

    //octo_prism - module that creates an oct_prism with anchors positioned on the faces instead of the edges (as per cyl default for 8 sides)
    module oct_prism(h, r=0, r1=0, r2=0, anchor=CENTER, spin=0, orient=UP) {
        attachable(anchor, spin, orient, size=[max(r*2, r1*2, r2*2), max(r*2, r1*2, r2*2), h]){ 
            down(h/2)
            if (r != 0) {
                // If r is provided, create a regular octagonal prism with radius r
                rotate (22.5) cylinder(h=h, r1=r, r2=r, $fn=8) rotate (-22.5);
            } else if (r1 != 0 && r2 != 0) {
                // If r1 and r2 are provided, create an octagonal prism with different top and bottom radii
                rotate (22.5) cylinder(h=h, r1=r1, r2=r2, $fn=8) rotate (-22.5);
            } else {
                echo("Error: You must provide either r or both r1 and r2.");
            }  
            children(); 
        }
    }
    
}
