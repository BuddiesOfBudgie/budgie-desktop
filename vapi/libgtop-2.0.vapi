[CCode (cprefix = "GTop", lower_case_cprefix = "glibtop_", cheader_filename = "glibtop.h,glibtop/cpu.h,glibtop/mem.h,glibtop/swap.h")]
namespace GTop {
    [CCode (cname = "glibtop_init")]
    public static void init();

    [CCode (cname = "glibtop_cpu", destroy_function = "", has_copy_function = false)]
    public struct Cpu {
        public uint64 total;
        public uint64 user;
        public uint64 nice;
        public uint64 sys;
        public uint64 idle;
        public uint64 iowait;
        public uint64 irq;
        public uint64 softirq;
    }

    [CCode (cname = "glibtop_get_cpu")]
    public static void get_cpu(out Cpu buf);

    [CCode (cname = "glibtop_mem", destroy_function = "", has_copy_function = false)]
    public struct Mem {
        public uint64 total;
        public uint64 used;
        public uint64 free;
        public uint64 shared;
        public uint64 buffer;
        public uint64 cached;
    }

    [CCode (cname = "glibtop_get_mem")]
    public static void get_mem(out Mem buf);

    [CCode (cname = "glibtop_swap", destroy_function = "", has_copy_function = false)]
    public struct Swap {
        public uint64 total;
        public uint64 used;
        public uint64 free;
    }

    [CCode (cname = "glibtop_get_swap")]
    public static void get_swap(out Swap buf);
}
