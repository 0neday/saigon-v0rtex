//
//  jailbreak.h
//  Saigon
//
//  Created by Abraham Masri on 10/14/17.
//  Copyright © 2017 cheesecakeufo. All rights reserved.
//

#ifndef jailbreak_h
#define jailbreak_h

kern_return_t mach_vm_read_overwrite(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, mach_vm_address_t data, mach_vm_size_t *outsize);
kern_return_t mach_vm_write(vm_map_t target_task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t dataCnt);
kern_return_t mach_vm_protect(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);
kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t *address, mach_vm_size_t size, int flags);


size_t kread(uint64_t where, void *p, size_t size);
size_t kwrite(uint64_t where, const void *p, size_t size);

uint64_t kread_uint64(uint64_t where);
size_t kwrite_uint64(uint64_t where, uint64_t value);

uint32_t kread_uint32(uint64_t where);
size_t kwrite_uint32(uint64_t where, uint32_t value);

void kx2(uint64_t fptr, uint64_t arg1, uint64_t arg2);
uint32_t kx5(uint64_t fptr, uint64_t arg1, uint64_t arg2, uint64_t arg3, uint64_t arg4, uint64_t arg5);


#endif /* jailbreak_h */
