package main

import (
	"encoding/binary"
	"fmt"
)

func main() {
	var af uint32 = 2
	rawBig := make([]byte, 4)
	binary.BigEndian.PutUint32(rawBig, af)
	
	rawLittle := make([]byte, 4)
	binary.LittleEndian.PutUint32(rawLittle, af)
	
	fmt.Printf("Big: %v\n", rawBig)
	fmt.Printf("Little: %v\n", rawLittle)
}
