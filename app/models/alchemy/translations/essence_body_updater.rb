module Alchemy
  module Translations
    class EssenceBodyUpdater

      def update_bodies(translations)
        Rails.logger.error "in update_bodies with #{translations}"

        locales = translations.keys

        locales.each do |locale|
          unless translations[locale]
            Rails.logger.error "Skipping locale: #{locale} b/c no changes"
            next
          end

          # :essence_key => { :locale => :id }
          all_translated_content = Alchemy::Translations::Cacher.new.all_translated_content
          all_translated_content.each_key do |essence_key|
            content_id = all_translated_content[essence_key][locale]

            # do we have an essence for this name/locale?
            if content_id
              Rails.logger.error "found content_id: #{content_id} for locale: #{locale}" if essence_key =~ /megacrate_winner_prize_3/
            else
              Rails.logger.error "no content for locale: #{locale}" if essence_key =~ /megacrate_winner_prize_3/
              next
            end

            # do we have a translation for this alchemy essence?
            begin
              translation = translations[locale][Alchemy::Translations::TRANSLATION_PREFIX][essence_key]
            rescue => e
              Rails.logger.error "Unable to locate translation: locale: #{locale} prefix: #{Alchemy::Translations::TRANSLATION_PREFIX} essence_key: #{essence_key}" if essence_key =~ /megacrate_winner_prize_3/
              nil
            end
            if translation
              Rails.logger.error "Updating essence: #{essence_key} (locale: #{locale}) with #{translation}" if essence_key =~ /megacrate_winner_prize_3/
              begin
                content = Alchemy::Content.find(content_id)
              rescue => e2
                Rails.logger.error "PROBLEM finding content for content_id #{content_id} : #{essence_key} (locale: #{locale})"
                nil
              end
              if content && content.essence && !content.skip_translate
                content.essence.update_column(:body, translation)
                if content.essence.kind_of? Alchemy::EssenceRichtext
                  content.essence.send(:strip_content)
                  content.essence.update_column(:stripped_body, content.essence.stripped_body)
                end

                # i hate having to do this, but:
                # irb(main):097:0* element
                #    => #<Alchemy::Element id: 224, name: "hiw_megacrate_info"....
                #
                # irb(main):098:0> element.essences.last
                #    => #<Alchemy::EssenceRichtext id: 771, body: "<p>Malachi is not ...
                #
                # irb(main):099:0> element.essences.last.reload
                #   => #<Alchemy::EssenceRichtext id: 771, body: "yyyy...
                content.essence.element.contents(true)
                content.essence.element.touch    # kill the fragment caching
                Rails.cache.clear                # come on man you are killing me..old shit take a hike man come on
              end
            else
              Rails.logger.error "NOT Updating essence: #{essence_key} (locale: #{locale}) - #{translations[locale][Alchemy::Translations::TRANSLATION_PREFIX]} - #{Alchemy::Translations::TRANSLATION_PREFIX}" if essence_key =~ /megacrate_winner_prize_3/
            end
          end
        end
      end
    end
  end
end
