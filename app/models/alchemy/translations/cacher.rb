module Alchemy
  module Translations
    class Cacher
      def all_translated_content
        data = Alchemy.redis.get('all_translatable_essences') || init_translatable_essences
        JSON.parse(data)
      end

      private
        def init_translatable_essences
          # :essence_name => { :locale => :essence_id }
          # let's populate our in-memory store
          t = Alchemy::Content.arel_table

          data = Hash.new
          Alchemy::Content.where(t[:essence_type].eq('Alchemy::EssenceText').or(
                                  t[:essence_type].eq('Alchemy::EssenceRichtext')).or(
                                  t[:essence_type].eq('Alchemy::EssenceHtml'))).each do |content|

            begin
              key_gen = Alchemy::Translations::HashKeyGenerator.new(content)
              key = key_gen.generate
              data[key] ||= {}
              data[key][content.essence.element.page.language.language_code] = content.id
            rescue => e
              Rails.logger.error "Alchemy Error - malformed content: #{content.name}"
            end
          end

          json = data.to_json
          Alchemy.redis.set('all_translatable_essences', json)
          json
        end
    end
  end
end
