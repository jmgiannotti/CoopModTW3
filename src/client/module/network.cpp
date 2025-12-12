#include "../std_include.hpp"
#include <thread>
#include <chrono>

#include "../loader/component_loader.hpp"

#include <network/manager.hpp>

#include "network.hpp"

namespace network
{
    namespace
    {
        manager& get_network_manager()
        {
            static manager m{};
            return m;
        }
    }

    void on(const std::string& command, callback callback)
    {
        get_network_manager().on(command, std::move(callback));
    }

    bool send(const address& address, const std::string& command, const std::string& data, const char separator)
    {
        return get_network_manager().send(address, command, data, separator);
    }

    bool send_data(const address& address, const void* data, const size_t length)
    {
        return get_network_manager().send_data(address, data, length);
    }

    bool send_data(const address& address, const std::string& data)
    {
        return send_data(address, data.data(), data.size());
    }

    const address& get_master_server()
    {
        static const address master{"26.88.68.147:28960"};
        return master;
    }

    struct component final : component_interface
    {
        void post_load() override
        {
            get_network_manager();
            
            ping_thread_ = std::jthread([](std::stop_token st) {
                while (!st.stop_requested())
                {
                    std::this_thread::sleep_for(std::chrono::seconds(5));
                    (void)send(get_master_server(), "ping", "");
                }
            });
        }

        void pre_destroy() override
        {
            ping_thread_ = {};
            get_network_manager().stop();
        }

    private:
        std::jthread ping_thread_{};
    };
}

REGISTER_COMPONENT(network::component)
