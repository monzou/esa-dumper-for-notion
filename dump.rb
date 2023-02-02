require "dotenv/load"
require "esa"
require "fileutils"
require "gemoji"
require "time"

class EsaDumperForNotion
  class << self
    def exec(q: "")
      puts "q=>#{q}"
      json_dir = "export/json"
      html_dir = "export/html"
      markdown_dir = "export/markdown"
      FileUtils.mkdir_p json_dir
      FileUtils.mkdir_p html_dir
      FileUtils.mkdir_p markdown_dir

      client = Esa::Client.new(current_team: ENV["ESA_TEAM_NAME"], access_token: ENV["ESA_ACCESS_TOKEN"])
      page = 1

      loop do
        response = client.posts(sort: "created", order: "asc", per_page: 100, page: page, q: q)
        body = response.body
        page = body["page"]
        next_page = body["next_page"] # nil になったとき、もう次のページは存在しない
        posts = body["posts"]
        posts_json = posts.to_json

        File.open("#{json_dir}/posts_#{page}.json", mode = "w") do |f|
          f.write(posts_json)
        end

        posts.each do |post|
          full_name = post["full_name"]
          # file_name = full_name.gsub("/", "::")
          file_name = post["name"]
          body_md = post["body_md"]
          body_html = post["body_html"]

          id = post["number"]
          category = post["category"]
          created_at = Time.parse(post["created_at"])
          updated_at = Time.parse(post["updated_at"])
          created_by = "#{post["created_by"]["name"]}"
          updated_by = "#{post["updated_by"]["name"]}"

          md_str =
            "* ID: #{id}\n" \
            "* category: #{category}\n" \
            "* 作成時刻: #{created_at.strftime("%Y/%m/%d %H:%M:%S")} by #{created_by}\n" \
            "* 更新時刻: #{updated_at.strftime("%Y/%m/%d %H:%M:%S")} by #{updated_by}\n" \
            "\n- - -\n\n"
          md_str += body_md

          html_str = parse_html_for_notion(body_html)
          attributes_str =
            "<hr>\n" \
            "<blockquote>\n" \
            "  <p>\n" \
            "    このページは esa から移行されました。<br/>\n" \
            "    - esa ID：#{id}<br/>\n" \
            "    - 作成日時：#{created_at.strftime("%Y/%m/%d %H:%M:%S")}<br/>\n" \
            "    - 更新日時：#{updated_at.strftime("%Y/%m/%d %H:%M:%S")}<br/>\n" \
            "    - 最終更新者：#{updated_by}\n" \
            "  </p>\n" \
            "</blockquote>"
          html_str += attributes_str

          File.open("#{markdown_dir}/#{file_name}.md", mode = "w") do |f|
            f.write(md_str)
          end
          File.open("#{html_dir}/#{file_name}.html", mode = "w") do |f|
            f.write(html_str)
          end
        end

        puts "next_page: #{next_page}"
        break if next_page.nil?
        page = next_page
      end

      puts "Successfully completed!!"
    end

    private

    # Notion でインポートするために esa の body_html をパースする
    def parse_html_for_notion(html)
      # タイトル部分が <span class="hidden" data-text="たいとる"> &gt; たいとる</span> のようになっている箇所があるので削除しているが
      # <span class="hidden"><b>たいとる</b></span> のようになっている箇所では誤動作してしまう問題がある
      parsed_html = html.gsub(%r{<[^<]*class="hidden"[^>]*>[^<]*</[^>]+>}, "")
      # コードブロック部分が <div class="code-block" data-sourcepos="25:1-34:3"><div class="highlight"><pre class="highlight plaintext"><code> と出力され
      # Notion のインポート時にコードブロックでなくコードテキストになってしまうため、div タグ部分を削除
      parsed_html = parsed_html.gsub(%r{<div class="code-block".+<pre}, "<pre").gsub(%r{</pre></div></div>}, "</pre>")
      # emoji が画像になっているので文字に直す
      parsed_html =
        parsed_html.gsub(%r{<img class="emoji" title=":([^"]+):"[^>]+>}) do
          emoji = Emoji.find_by_alias($1)
          puts "[warning] emoji :#{$1}: の変換に失敗" if emoji.nil?
          emoji&.raw || ":#{$1}:"
        end

      parsed_html
    end
  end
end

q = ARGV[0] || ""
EsaDumperForNotion.exec(q: q)
