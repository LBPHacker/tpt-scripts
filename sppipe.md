% Single-pixel pipe configurator script
% LBPHacker
% 2023-12-24

# Single-pixel pipe configurator script

This script adds a single element: SPPC, the single-pixel pipe configurator.

Basic usage is as simple as drawing a one pixel wide line of SPPC where you want
PIPE/PPIP to appear, and once satisfied, clicking on either end of the line with
PIPE/PPIP. This either results in the SPPC line being converted into the pipe
type of choice, or some error message regarding why the conversion cannot be
done. If conversion succeeds, the clicked end will be the input of the pipe.

Note that the process prefers non-diagonal neighbours over diagonal ones. This
is done so free-form drawn lines of SPPC can be converted to pipes easily, even
if they include L-shaped parts, which would be considered forks otherwise.

Advanced usage involves *adjacency domains*, which let you cross lines of SPPC
and still have them convert into different pipes that don't leak into one
another. SPPC considers itself *logically* adjacent to any other, *physically*
adjacent SPPC if their `.tmp` values match, or if one of them has a `.life` value
that matches the `.tmp` value of the other. Physical adjacency is just being
adjacent on the pixel grid. Logical adjacency is what matters when discovering
the bounds of the pipe to be converted.

`.tmp` values must be positive numbers. Adjust them either with the PROP tool or
by changing the default `.tmp` for SPPC upon spawning with brush size controls or
the number keys while you have SPPC selected. The description and the colour of
the element button will reflect the current default `.tmp`. It's also possible to
sample the `.tmp` of SPPC with the sample tool.

SPPC of different `.tmp` are rendered with different, vibrant colours. A special
case is non-zero `.life` SPPC, which is rendered with white, indicating that it acts
as a bridge between SPPC domains.

Drawing SPPC over any particle (the way you would normally set the ctype of
CLNE, for example) of a correctly configured single-pixel pipe converts the
entire pipe into SPPC, using as few bridge particles as possible.
