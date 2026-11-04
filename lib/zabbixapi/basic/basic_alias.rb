class ZabbixApi
  class Basic
    # Alias of {#get_full_data}
    #
    # @param (see #get_full_data)
    # @return (see #get_full_data)
    def get(data)
      get_full_data(data)
    end

    # Alias of {#create}
    #
    # @param (see #create)
    # @return (see #create)
    def add(data)
      create(data)
    end

    # Alias of {#delete}
    #
    # @param (see #delete)
    # @return (see #delete)
    def destroy(data)
      delete(data)
    end
  end
end
