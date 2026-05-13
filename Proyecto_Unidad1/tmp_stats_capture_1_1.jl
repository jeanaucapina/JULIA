path = joinpath(pwd(), "Proyecto_Unidad1", "iot_23_datasets_small", "opt", "Malware-Project", "BigDataset", "IoTScenarios", "CTU-IoT-Malware-Capture-1-1", "bro", "conn.log.labeled")

let
    ip_out = Dict{String,Int}()
    ip_in = Dict{String,Int}()
    edges = Set{Tuple{String,String}}()
    n = 0

    open(path, "r") do fh
        for line in eachline(fh)
            startswith(line, '#') && continue
            n += 1
            n > 150000 && break
            cols = split(line, '\t')
            length(cols) < 6 && continue
            s = cols[3]
            d = cols[5]
            ip_out[s] = get(ip_out, s, 0) + 1
            ip_in[d] = get(ip_in, d, 0) + 1
            s != d && push!(edges, (s, d))
        end
    end

    all_ips = union(Set(keys(ip_out)), Set(keys(ip_in)))
    max_out_ip, max_out = "", -1
    for (k, v) in ip_out
        if v > max_out
            max_out = v
            max_out_ip = k
        end
    end

    hub_dsts = Set{String}()
    for (s, d) in edges
        s == max_out_ip && push!(hub_dsts, d)
    end

    println("rows=", n)
    println("unique_src=", length(keys(ip_out)))
    println("unique_dst=", length(keys(ip_in)))
    println("all_ips=", length(all_ips))
    println("unique_edges=", length(edges))
    println("max_out_ip=", max_out_ip, " out_conn=", max_out)
    println("hub_unique_dsts=", length(hub_dsts))
    println("hub_share_edges=", round(length(hub_dsts) / max(length(edges), 1) * 100, digits = 2), "%")
end
