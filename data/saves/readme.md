# Save Files
Qonquest saves are in the .qsf (Quonquest Save File) format.
Each save begins with ushort telling which version the format is in
(note: CString = Zero-Terminated ASCII String)
## Version 0
```
ushort format; // always 0
ushort data; // where the compressed script begins
CString country; // tag of the player country
```
From `data` onwards is a script (.qsc) compressed using std.zlib's `compress` function.