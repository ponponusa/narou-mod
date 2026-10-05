# frozen_string_literal: true

require "lib/cli/command/reparse"
require "lib/cli/command/convert"

RSpec.describe Command::Reparse do
  let(:command) { described_class.new }
  let(:data) { { "id" => 1, "title" => "テスト小説" } }
  let(:downloader) { instance_double(Downloader) }
  let(:result) { { changed: [{ "index" => "1" }], unchanged: 2, skipped: 0, failed: 0 } }

  before do
    allow(command).to receive(:tagname_to_ids)
    allow(command).to receive(:error)
    allow(Downloader).to receive(:get_data_by_target).with("n1234ab").and_return(data)
    allow(Downloader).to receive(:new).with("n1234ab").and_return(downloader)
    allow(Narou).to receive(:novel_frozen?).with("n1234ab").and_return(false)
    allow(downloader).to receive(:reparse_sections_from_raw).and_return(result)
    allow(Command::Convert).to receive(:execute!).and_return(0)
  end

  def run(*argv)
    status = nil
    output = capture_stdout { status = command.execute!(*argv) }
    [status, output]
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it "引数が無い場合はヘルプを表示する" do
    expect(command).to receive(:display_help!).and_raise(SystemExit)
    command.execute!
  end

  it "解析し直して本文が変わった小説を変換する" do
    status, output = run("n1234ab")

    expect(status).to eq 0
    expect(downloader).to have_received(:reparse_sections_from_raw).with(dry_run: nil)
    expect(Command::Convert).to have_received(:execute!).with("n1234ab")
    expect(output).to include("更新あり 1 話、変更なし 2 話")
  end

  it "本文が変わらなかった小説は変換しない" do
    result[:changed] = []

    status, = run("n1234ab")

    expect(status).to eq 0
    expect(Command::Convert).not_to have_received(:execute!)
  end

  it "--no-convert を指定すると変換しない" do
    status, = run("n1234ab", "--no-convert")

    expect(status).to eq 0
    expect(Command::Convert).not_to have_received(:execute!)
  end

  it "--dry-run では保存せず変換もしない" do
    status, output = run("n1234ab", "--dry-run")

    expect(status).to eq 0
    expect(downloader).to have_received(:reparse_sections_from_raw).with(dry_run: true)
    expect(Command::Convert).not_to have_received(:execute!)
    expect(output).to include("--dry-run のため保存していません")
  end

  it "失敗した話がある場合は終了コードで知らせる" do
    result[:failed] = 1

    status, output = run("n1234ab")

    expect(status).to eq 1
    expect(output).to include("失敗 1 話")
  end

  it "存在しない小説はエラーにする" do
    allow(Downloader).to receive(:get_data_by_target).with("invalid").and_return(nil)

    status, = run("invalid")

    expect(status).to eq 1
    expect(command).to have_received(:error).with(include("invalid は存在しません"))
  end

  it "凍結中の小説は解析し直さない" do
    allow(Narou).to receive(:novel_frozen?).with("n1234ab").and_return(true)

    status, = run("n1234ab")

    expect(status).to eq 1
    expect(downloader).not_to have_received(:reparse_sections_from_raw)
    expect(command).to have_received(:error).with(include("凍結中"))
  end
end
