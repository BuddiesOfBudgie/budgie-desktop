public class Up.Client : GLib.Object {
    [CCode (cname = "up_client_new_async", has_construct_function = false)]
    [Version (since = "0.99.14")]
    public async Client.@async (GLib.Cancellable? cancellable = null) throws GLib.Error;
}
