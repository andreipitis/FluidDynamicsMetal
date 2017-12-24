# FluidDynamicsMetal
A fluid dynamics implementation using Metal for iOS and OSX.

![fluiddynamics](https://github.com/andreipitis/FluidDynamicsMetal/blob/master/FluidDynamicsMetal.gif?raw=true)

## Usage

There are two targets in this project, simply select the scheme of the one you wish to see and build it:

 ### 1. `FluidDynamicsMetaliOS`
 
Interaction for the `iOS` version is done through touch events, simply touch the screen and swipe in order to interact with the fluid.
 
 - A *single finger double tap* pauses or resumes the simulation.
 
 - A *two finger double tap* changes the surface that is drawn. 
By default, the density field is displayed, but you can also see the pressure, velocity or the surface used for computing the vorticity (smoke-like swirlies).
 
 ### 2. `FluidDynamicsMetalOSX`
  
Interacting with the `OSX` version is similar, you use the *mouse* to interact with the fluid, the *space bar* to pause the simulation and the *S key* to change the surface.
 
 ## Changing parameters
 
Right now there is no settings view to select and configure the various parameters of the simulation, so if you wish to change some of the values and see how it affects the result, you're going to have to change the code for the shaders.

## Understanding the simulation

If you wish to understand how all of this works, take a look [here](http://developer.download.nvidia.com/books/HTML/gpugems/gpugems_ch38.html) or [here](http://prideout.net/blog/?p=58). These are some of the sources I used when creating the simulation.
