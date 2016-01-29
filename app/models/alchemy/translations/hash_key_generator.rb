module Alchemy
  module Translations
    class HashKeyGenerator
      def initialize(content)
        @content = content
      end
      def generate
        element = @content.essence.element
        page = element.page.name
        position = element.position
        "#{page}_#{@content.name}_pos_#{position}"
      end
    end
  end
end
